const AWS = require("aws-sdk");

const dynamodb = new AWS.DynamoDB.DocumentClient();
const sns = new AWS.SNS();

const {
  AVAILABILITY_REQUESTS_TABLE,
  SWAP_REQUESTS_TABLE,
  CHANGE_PROPOSALS_TABLE,
  SNS_TOPIC_ARN,
  USER_PROFILES_TABLE,
  STRIPE_SECRET_KEY,
  WEBHOOK_STALE_HOURS,
} = process.env;

const daysAgo = (days) => {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return date;
};

const scanPending = async (tableName, statusKey = "status") => {
  const items = [];
  let lastKey = undefined;
  do {
    const result = await dynamodb
      .scan({
        TableName: tableName,
        FilterExpression: "#status = :pending",
        ExpressionAttributeNames: { "#status": statusKey },
        ExpressionAttributeValues: { ":pending": "pending" },
        ExclusiveStartKey: lastKey,
      })
      .promise();
    items.push(...(result.Items || []));
    lastKey = result.LastEvaluatedKey;
  } while (lastKey);
  return items;
};

const stripeRequest = async ({ path, method = "GET" }) => {
  if (!STRIPE_SECRET_KEY) {
    throw new Error("Stripe secret key not configured");
  }
  const response = await fetch(`https://api.stripe.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
  });
  const text = await response.text();
  let data = {};
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text };
  }
  if (!response.ok) {
    const message = data?.error?.message || `Stripe error (${response.status})`;
    const err = new Error(message);
    err.statusCode = response.status;
    err.details = data;
    throw err;
  }
  return data;
};

const getBillingSystemRecord = async () => {
  if (!USER_PROFILES_TABLE) return null;
  const record = await dynamodb
    .get({
      TableName: USER_PROFILES_TABLE,
      Key: { userId: "system#billing" },
    })
    .promise();
  return record.Item || null;
};

const updateBillingSystemRecord = async (patch) => {
  if (!USER_PROFILES_TABLE) return;
  const now = new Date().toISOString();
  const expression = ["updatedAt = :updatedAt"];
  const values = { ":updatedAt": now };
  const names = {};
  Object.entries(patch || {}).forEach(([key, value], index) => {
    const nameKey = `#k${index}`;
    const valueKey = `:v${index}`;
    names[nameKey] = key;
    values[valueKey] = value;
    expression.push(`${nameKey} = ${valueKey}`);
  });
  await dynamodb
    .update({
      TableName: USER_PROFILES_TABLE,
      Key: { userId: "system#billing" },
      UpdateExpression: `SET ${expression.join(", ")}`,
      ExpressionAttributeNames: Object.keys(names).length ? names : undefined,
      ExpressionAttributeValues: values,
    })
    .promise();
};

const normalizePlan = (plan, prices = {}) => {
  if (!plan) return "";
  const normalized = plan.toString().toLowerCase();
  if (["starter", "operations", "enterprise"].includes(normalized)) {
    return normalized;
  }
  if (prices.starter && normalized === prices.starter.toLowerCase()) {
    return "starter";
  }
  if (prices.operations && normalized === prices.operations.toLowerCase()) {
    return "operations";
  }
  if (prices.enterprise && normalized === prices.enterprise.toLowerCase()) {
    return "enterprise";
  }
  return normalized;
};

const pickBestSubscription = (subscriptions = []) => {
  if (!Array.isArray(subscriptions) || subscriptions.length === 0) return null;
  const active = subscriptions.find((s) =>
    ["active", "trialing"].includes((s.status || "").toLowerCase())
  );
  if (active) return active;
  return subscriptions
    .slice()
    .sort((a, b) => (b.current_period_end || 0) - (a.current_period_end || 0))[0];
};

const reconcileBilling = async () => {
  if (!USER_PROFILES_TABLE) {
    return { ok: false, reason: "USER_PROFILES_TABLE missing" };
  }
  if (!STRIPE_SECRET_KEY) {
    return { ok: false, reason: "STRIPE_SECRET_KEY missing" };
  }
  await updateBillingSystemRecord({
    lastReconcileAt: new Date().toISOString(),
    lastReconcileSource: "scheduler",
    lastReconcileStatus: "running",
  });
  const results = {
    scanned: 0,
    updated: 0,
    skipped: 0,
    errors: 0,
  };
  let lastKey = undefined;
  const startedAt = Date.now();
  do {
    const response = await dynamodb
      .scan({
        TableName: USER_PROFILES_TABLE,
        ProjectionExpression:
          "userId, email, stripeCustomerId, subscriptionStatus, subscriptionPlan",
        ExclusiveStartKey: lastKey,
      })
      .promise();
    const items = response.Items || [];
    for (const item of items) {
      if (!item.userId || item.userId === "system#billing") continue;
      results.scanned += 1;
      const customerId = item.stripeCustomerId;
      const email = item.email || "";
      if (!customerId && !email) {
        results.skipped += 1;
        continue;
      }
      try {
        let resolvedCustomerId = customerId;
        if (!resolvedCustomerId && email) {
          const customers = await stripeRequest({
            path: `/v1/customers?email=${encodeURIComponent(email)}&limit=5`,
          });
          const list = customers?.data || [];
          if (list.length > 0) {
            resolvedCustomerId = list[0].id;
          }
        }
        if (!resolvedCustomerId) {
          results.skipped += 1;
          continue;
        }
        const subsResponse = await stripeRequest({
          path: `/v1/subscriptions?customer=${encodeURIComponent(
            resolvedCustomerId
          )}&status=all&limit=10`,
        });
        const subscription = pickBestSubscription(subsResponse?.data || []);
        if (!subscription) {
          results.skipped += 1;
          continue;
        }
        const plan =
          subscription.metadata?.plan ||
          subscription.items?.data?.[0]?.price?.id ||
          "";
        const periodEnd = subscription.current_period_end
          ? new Date(subscription.current_period_end * 1000).toISOString()
          : null;
        await dynamodb
          .update({
            TableName: USER_PROFILES_TABLE,
            Key: { userId: item.userId },
            UpdateExpression:
              "SET subscriptionStatus = :status, subscriptionPlan = :plan, stripeCustomerId = :customerId, stripeSubscriptionId = :subId, subscriptionPeriodEnd = :periodEnd, updatedAt = :updatedAt",
            ExpressionAttributeValues: {
              ":status": subscription.status || "inactive",
              ":plan": normalizePlan(plan),
              ":customerId": resolvedCustomerId,
              ":subId": subscription.id,
              ":periodEnd": periodEnd,
              ":updatedAt": new Date().toISOString(),
            },
          })
          .promise();
        results.updated += 1;
      } catch (error) {
        results.errors += 1;
        console.error("Billing reconcile user failed", item.userId, error);
      }
      if (Date.now() - startedAt > 20000) {
        break;
      }
    }
    lastKey = response.LastEvaluatedKey;
    if (Date.now() - startedAt > 20000) {
      break;
    }
  } while (lastKey);
  await updateBillingSystemRecord({
    lastReconcileStatus: "ok",
    lastReconcileSummary: results,
  });
  return { ok: true, results };
};

const checkWebhookHealth = async () => {
  if (!SNS_TOPIC_ARN || !USER_PROFILES_TABLE) return;
  const record = await getBillingSystemRecord();
  const lastWebhookAt = record?.lastWebhookAt;
  if (!lastWebhookAt) {
    await sns
      .publish({
        TopicArn: SNS_TOPIC_ARN,
        Subject: "Roster Champ - Stripe webhook missing",
        Message: "No Stripe webhook has been received yet.",
      })
      .promise();
    return;
  }
  const hours = Number(WEBHOOK_STALE_HOURS || "36");
  const last = new Date(lastWebhookAt).getTime();
  if (Number.isNaN(last)) return;
  const ageHours = (Date.now() - last) / (1000 * 60 * 60);
  if (ageHours >= hours) {
    await sns
      .publish({
        TopicArn: SNS_TOPIC_ARN,
        Subject: "Roster Champ - Stripe webhook stale",
        Message: `Last webhook received at ${lastWebhookAt}. Age: ${ageHours.toFixed(
          1
        )} hours.`,
      })
      .promise();
  }
};

exports.handler = async (event = {}) => {
  if (!SNS_TOPIC_ARN) {
    return { ok: false, reason: "SNS_TOPIC_ARN not configured" };
  }

  if (event?.action === "reconcileBilling") {
    await checkWebhookHealth();
    return reconcileBilling();
  }

  await checkWebhookHealth();
  await reconcileBilling();
  const cutoff = daysAgo(30);
  const availability = await scanPending(AVAILABILITY_REQUESTS_TABLE);
  const swaps = await scanPending(SWAP_REQUESTS_TABLE);
  const proposals = await scanPending(CHANGE_PROPOSALS_TABLE);

  const recentAvailability = availability.filter(
    (item) => new Date(item.createdAt || item.updatedAt || 0) >= cutoff
  );
  const recentSwaps = swaps.filter(
    (item) => new Date(item.createdAt || item.updatedAt || 0) >= cutoff
  );
  const recentProposals = proposals.filter(
    (item) => new Date(item.createdAt || item.updatedAt || 0) >= cutoff
  );

  const message = {
    summary: "Pending approvals summary",
    counts: {
      availability: recentAvailability.length,
      swaps: recentSwaps.length,
      proposals: recentProposals.length,
    },
    generatedAt: new Date().toISOString(),
  };

  await sns
    .publish({
      TopicArn: SNS_TOPIC_ARN,
      Subject: "Roster Champ - Pending approvals",
      Message: JSON.stringify(message, null, 2),
    })
    .promise();

  return { ok: true };
};
