const AWS = require("aws-sdk");
const crypto = require("crypto");

const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const sns = new AWS.SNS();
const ses = new AWS.SES({ region: process.env.SES_REGION || process.env.AWS_REGION });
const bedrock = new AWS.BedrockRuntime({
  region: process.env.BEDROCK_REGION || process.env.AWS_REGION,
});
const cognito = new AWS.CognitoIdentityServiceProvider();
const secretsManager = new AWS.SecretsManager();

const {
  ROSTERS_TABLE,
  ROSTER_MEMBERS_TABLE,
  ROSTER_DATA_TABLE,
  ROSTER_UPDATES_TABLE,
  ORGS_TABLE,
  ORG_MEMBERS_TABLE,
  TEAMS_TABLE,
  TEAM_MEMBERS_TABLE,
  AVAILABILITY_REQUESTS_TABLE,
  SWAP_REQUESTS_TABLE,
  SHIFT_LOCKS_TABLE,
  CHANGE_PROPOSALS_TABLE,
  AUDIT_LOGS_TABLE,
  SHARE_CODES_TABLE,
  PRESENCE_TABLE,
  TIME_CLOCK_TABLE,
  AI_FEEDBACK_TABLE,
  ANALYTICS_TABLE,
  EXPORTS_BUCKET,
  CLOUDFRONT_URL,
  SNS_TOPIC_ARN,
  SES_FROM,
  USER_PROFILES_TABLE,
  ROSTER_VERSIONS_TABLE,
  TRIAL_HISTORY_TABLE,
  ROSTER_SALT,
  BEDROCK_MODEL_ID,
  USER_POOL_ID,
  APP_CONFIG_SECRET_ARN,
  BILLING_EVENTS_BUS,
} = process.env;

let cachedAppSecrets = null;
let cachedAppSecretsAt = 0;
let lastSecretsError = null;
const APP_SECRETS_CACHE_MS = 5 * 60 * 1000;
const ROSTER_VERSION_SNAPSHOT_INTERVAL = 20;
const ROSTER_VERSION_MAX_OPS = 500;

const isObject = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const deepClone = (value) =>
  value == null ? value : JSON.parse(JSON.stringify(value));

const normalizePath = (segments) =>
  "/" +
  segments
    .map((segment) =>
      segment.toString().replace(/~/g, "~0").replace(/\//g, "~1")
    )
    .join("/");

const diffJson = (oldValue, newValue, pathSegments = [], ops = [], summary = new Set()) => {
  if (oldValue === undefined && newValue === undefined) {
    return { ops, summary };
  }
  if (oldValue === undefined) {
    ops.push({ op: "add", path: normalizePath(pathSegments), value: newValue });
    if (pathSegments.length > 0) summary.add(pathSegments[0]);
    return { ops, summary };
  }
  if (newValue === undefined) {
    ops.push({ op: "remove", path: normalizePath(pathSegments) });
    if (pathSegments.length > 0) summary.add(pathSegments[0]);
    return { ops, summary };
  }

  if (Array.isArray(oldValue) || Array.isArray(newValue)) {
    const oldJson = JSON.stringify(oldValue);
    const newJson = JSON.stringify(newValue);
    if (oldJson !== newJson) {
      ops.push({
        op: "replace",
        path: normalizePath(pathSegments),
        value: newValue,
      });
      if (pathSegments.length > 0) summary.add(pathSegments[0]);
    }
    return { ops, summary };
  }

  if (isObject(oldValue) && isObject(newValue)) {
    const keys = new Set([
      ...Object.keys(oldValue),
      ...Object.keys(newValue),
    ]);
    for (const key of keys) {
      diffJson(
        oldValue[key],
        newValue[key],
        [...pathSegments, key],
        ops,
        summary
      );
    }
    return { ops, summary };
  }

  if (oldValue !== newValue) {
    ops.push({
      op: "replace",
      path: normalizePath(pathSegments),
      value: newValue,
    });
    if (pathSegments.length > 0) summary.add(pathSegments[0]);
  }
  return { ops, summary };
};

const applyPatch = (base, ops) => {
  let root = deepClone(base);
  const getTarget = (obj, segments) => {
    let node = obj;
    for (let i = 0; i < segments.length - 1; i += 1) {
      const segment = segments[i];
      if (node[segment] === undefined) {
        node[segment] = {};
      }
      node = node[segment];
    }
    return node;
  };
  const decode = (path) =>
    path
      .split("/")
      .slice(1)
      .map((segment) => segment.replace(/~1/g, "/").replace(/~0/g, "~"));

  for (const op of ops || []) {
    const path = op.path || "";
    if (path === "/" || path === "") {
      if (op.op === "remove") {
        root = null;
      } else if (op.op === "add" || op.op === "replace") {
        root = deepClone(op.value);
      }
      continue;
    }
    const segments = decode(path);
    const key = segments[segments.length - 1];
    const target = getTarget(root, segments);
    if (Array.isArray(target)) {
      const index = key === "-" ? target.length : Number(key);
      if (op.op === "remove") {
        if (!Number.isNaN(index)) target.splice(index, 1);
      } else if (op.op === "add") {
        if (!Number.isNaN(index)) target.splice(index, 0, deepClone(op.value));
      } else if (op.op === "replace") {
        if (!Number.isNaN(index)) target[index] = deepClone(op.value);
      }
    } else {
      if (op.op === "remove") {
        delete target[key];
      } else if (op.op === "add" || op.op === "replace") {
        target[key] = deepClone(op.value);
      }
    }
  }
  return root;
};

const writeRosterVersionEntry = async ({
  rosterId,
  version,
  baseVersion,
  fromVersion,
  userId,
  reason,
  patch,
  changedSections,
  snapshot,
  timestamp,
}) => {
  if (!ROSTER_VERSIONS_TABLE) return;
  await dynamodb
    .put({
      TableName: ROSTER_VERSIONS_TABLE,
      Item: {
        rosterId,
        version,
        baseVersion: baseVersion ?? null,
        fromVersion: fromVersion ?? null,
        userId,
        reason: reason || "",
        diff: patch || [],
        diffCount: patch?.length ?? 0,
        changedSections: changedSections || [],
        snapshot: snapshot ?? null,
        timestamp,
      },
    })
    .promise();
};

async function loadAppSecrets(force = false) {
  if (force) {
    cachedAppSecrets = null;
    cachedAppSecretsAt = 0;
  }
  if (
    cachedAppSecrets &&
    Date.now() - cachedAppSecretsAt < APP_SECRETS_CACHE_MS
  ) {
    return cachedAppSecrets;
  }
  if (!APP_CONFIG_SECRET_ARN) {
    cachedAppSecrets = {};
    return cachedAppSecrets;
  }
  try {
    const secret = await secretsManager
      .getSecretValue({ SecretId: APP_CONFIG_SECRET_ARN })
      .promise();
    if (secret.SecretString) {
      const raw = secret.SecretString.replace(/^\uFEFF/, "");
      const cleaned = raw.replace(/^\u00EF\u00BB\u00BF/, "").replace(/^[^\{\[]+/, "");
      cachedAppSecrets = JSON.parse(cleaned);
      cachedAppSecretsAt = Date.now();
      lastSecretsError = null;
    } else {
      cachedAppSecrets = {};
      cachedAppSecretsAt = Date.now();
      lastSecretsError = "SecretString was empty";
    }
  } catch (err) {
    console.error("Failed to load app secrets", err);
    cachedAppSecrets = {};
    cachedAppSecretsAt = Date.now();
    lastSecretsError = err?.message || String(err);
  }
  return cachedAppSecrets;
}

async function getRuntimeConfig({ forceSecretsReload = false } = {}) {
  const secrets = await loadAppSecrets(forceSecretsReload);
  const bedrockModelId =
    secrets.bedrockModelId ||
    BEDROCK_MODEL_ID ||
    "anthropic.claude-3-haiku-20240307-v1:0";
  return {
    sesFrom: secrets.sesFrom || SES_FROM,
    bedrockModelId,
    stripe: {
      secretKey: secrets.stripe?.secretKey || "",
      publishableKey: secrets.stripe?.publishableKey || "",
      webhookSecret: secrets.stripe?.webhookSecret || "",
      prices: {
        starter: secrets.stripe?.prices?.starter || "",
        operations: secrets.stripe?.prices?.operations || "",
        enterprise: secrets.stripe?.prices?.enterprise || "",
      },
      successUrl: secrets.stripe?.successUrl || "",
      cancelUrl: secrets.stripe?.cancelUrl || "",
      portalReturnUrl: secrets.stripe?.portalReturnUrl || "",
    },
    updateUrls: {
      default: secrets.updateUrls?.default || process.env.UPDATE_URL || "",
      android: secrets.updateUrls?.android || process.env.UPDATE_URL_ANDROID || "",
      windows: secrets.updateUrls?.windows || process.env.UPDATE_URL_WINDOWS || "",
      linux: secrets.updateUrls?.linux || process.env.UPDATE_URL_LINUX || "",
      ios: secrets.updateUrls?.ios || process.env.UPDATE_URL_IOS || "",
      macos: secrets.updateUrls?.macos || process.env.UPDATE_URL_MACOS || "",
    },
    minVersions: {
      default: secrets.minVersions?.default || process.env.MIN_APP_VERSION || "",
      android:
        secrets.minVersions?.android || process.env.MIN_APP_VERSION_ANDROID || "",
      windows:
        secrets.minVersions?.windows || process.env.MIN_APP_VERSION_WINDOWS || "",
      linux: secrets.minVersions?.linux || process.env.MIN_APP_VERSION_LINUX || "",
      ios: secrets.minVersions?.ios || process.env.MIN_APP_VERSION_IOS || "",
      macos: secrets.minVersions?.macos || process.env.MIN_APP_VERSION_MACOS || "",
    },
      latestVersions: {
        default:
          secrets.latestVersions?.default || process.env.LATEST_APP_VERSION || "",
        android:
        secrets.latestVersions?.android ||
        process.env.LATEST_APP_VERSION_ANDROID ||
        "",
      windows:
        secrets.latestVersions?.windows ||
        process.env.LATEST_APP_VERSION_WINDOWS ||
        "",
      linux:
        secrets.latestVersions?.linux || process.env.LATEST_APP_VERSION_LINUX || "",
      ios:
        secrets.latestVersions?.ios || process.env.LATEST_APP_VERSION_IOS || "",
      macos:
        secrets.latestVersions?.macos ||
        process.env.LATEST_APP_VERSION_MACOS ||
        "",
    },
    usageQuotas: secrets.usageQuotas || {},
    usageCosts: secrets.usageCosts || {},
    usageHardCaps: secrets.usageHardCaps || {},
    costBudget: secrets.costBudget || {},
  };
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization,content-type",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
};

const jsonResponse = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json", ...corsHeaders },
  body: JSON.stringify(body),
});

const parseBody = (event) => {
  if (!event.body) return {};
  try {
    return JSON.parse(event.body);
  } catch {
    return {};
  }
};

const getRawBody = (event) => {
  if (!event.body) return Buffer.from("");
  const buffer = event.isBase64Encoded
    ? Buffer.from(event.body, "base64")
    : Buffer.from(event.body, "utf8");
  return buffer;
};

const stripeSignatureHeader = (event) =>
  event.headers?.["stripe-signature"] || event.headers?.["Stripe-Signature"] || "";

const verifyStripeSignature = (rawBody, signatureHeader, secret) => {
  if (!secret || !signatureHeader) return false;
  const parts = signatureHeader.split(",").map((part) => part.trim());
  const timestamp = parts.find((p) => p.startsWith("t="))?.split("=")[1];
  const signature = parts.find((p) => p.startsWith("v1="))?.split("=")[1];
  if (!timestamp || !signature) return false;
  const payload = `${timestamp}.${rawBody.toString("utf8")}`;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(payload, "utf8")
    .digest("hex");
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expected, "hex"),
      Buffer.from(signature, "hex")
    );
  } catch {
    return false;
  }
};

const stripeRequest = async ({
  path,
  method = "POST",
  body,
  secretKey,
  stripeVersion,
  extraHeaders,
}) => {
  if (!secretKey) {
    throw new Error("Stripe secret key not configured");
  }
  const response = await fetch(`https://api.stripe.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
      ...(stripeVersion ? { "Stripe-Version": stripeVersion } : {}),
      ...(extraHeaders || {}),
    },
    body: body ? new URLSearchParams(body).toString() : undefined,
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

const stripeGet = async ({ path, secretKey, stripeVersion }) =>
  stripeRequest({ path, method: "GET", secretKey, stripeVersion });

const FX_SYMBOLS = ["GBP", "EUR", "JPY", "CNY", "INR"];
const FX_CACHE_MS = 24 * 60 * 60 * 1000;

const fetchFxRates = async () => {
  const url = `https://api.exchangerate.host/latest?base=USD&symbols=${FX_SYMBOLS.join(",")}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`FX rates fetch failed (${response.status})`);
  }
  const data = await response.json();
  if (!data || !data.rates) {
    throw new Error("FX rates invalid response");
  }
  return {
    base: data.base || "USD",
    rates: data.rates || {},
    date: data.date || null,
  };
};

const getFxRatesCached = async () => {
  const record = await getBillingSystemRecord();
  const updatedAt = record?.fxUpdatedAt ? Date.parse(record.fxUpdatedAt) : 0;
  const now = Date.now();
  if (record?.fxRates && updatedAt && now - updatedAt < FX_CACHE_MS) {
    return { ...record.fxRates, updatedAt: record.fxUpdatedAt, cached: true };
  }
  try {
    const fresh = await fetchFxRates();
    const payload = {
      base: fresh.base || "USD",
      rates: fresh.rates || {},
      date: fresh.date || null,
      updatedAt: new Date().toISOString(),
      cached: false,
    };
    await updateBillingSystemRecord({
      fxRates: {
        base: payload.base,
        rates: payload.rates,
        date: payload.date,
      },
      fxUpdatedAt: payload.updatedAt,
    });
    return payload;
  } catch (error) {
    console.warn("FX rates fetch failed, using cached", error);
    if (record?.fxRates) {
      return {
        ...record.fxRates,
        updatedAt: record.fxUpdatedAt || null,
        cached: true,
        stale: true,
      };
    }
    throw error;
  }
};

const getUserId = (event) =>
  event?.requestContext?.authorizer?.jwt?.claims?.sub ||
  event?.requestContext?.authorizer?.iam?.cognitoIdentity?.identityId ||
  event?.requestContext?.identity?.cognitoIdentityId ||
  null;

const getUserEmail = (event) =>
  event?.requestContext?.authorizer?.jwt?.claims?.email || null;

const getUserGroups = (event) => {
  const groups = event?.requestContext?.authorizer?.jwt?.claims?.["cognito:groups"];
  if (!groups) return [];
  if (Array.isArray(groups)) return groups;
  if (typeof groups === "string") {
    return groups.split(",").map((g) => g.trim()).filter(Boolean);
  }
  return [];
};

const isAdminUser = (event) => {
  const groups = getUserGroups(event);
  return groups.includes("Admins");
};

const updateSubscriptionRecord = async ({
  userId,
  customerId,
  status,
  plan,
  subscriptionId,
  currentPeriodEnd,
  config,
}) => {
  if (!userId) return;
  const normalizedPlan = normalizePlan(plan, config);
  const now = new Date().toISOString();
  await dynamodb
    .update({
      TableName: USER_PROFILES_TABLE,
      Key: { userId },
      UpdateExpression:
        "SET subscriptionStatus = :status, subscriptionPlan = :plan, stripeCustomerId = :customerId, stripeSubscriptionId = :subId, subscriptionPeriodEnd = :periodEnd, updatedAt = :updatedAt",
      ExpressionAttributeValues: {
        ":status": status ?? "inactive",
        ":plan": normalizedPlan ?? "",
        ":customerId": customerId ?? "",
        ":subId": subscriptionId ?? "",
        ":periodEnd": currentPeriodEnd ?? null,
        ":updatedAt": now,
      },
    })
    .promise();
};

const enforceShareCodeLimitsForUser = async ({
  userId,
  status,
  plan,
  config,
}) => {
  if (!userId) return;
  const normalizedPlan = normalizePlan(plan, config);
  const statusLower = (status || "").toLowerCase();
  const suspendedStatuses = [
    "canceled",
    "cancelled",
    "unpaid",
    "incomplete_expired",
    "paused",
  ];
  const isActive = statusLower === "active" || statusLower === "trialing";
  if (!isActive && suspendedStatuses.includes(statusLower)) {
    await revokeShareCodes({
      userId,
      keepNewestCount: 0,
      reason: "subscription_inactive",
    });
    return;
  }
  const limits = sharePlanLimits(normalizedPlan);
  if (!limits.maxUses) {
    await revokeShareCodes({
      userId,
      keepNewestCount: 0,
      reason: "subscription_inactive",
    });
    return;
  }
  await revokeShareCodes({
    userId,
    keepNewestCount: limits.maxUses,
    reason: "plan_downgrade",
  });
};

const findUserIdByCustomer = async (customerId) => {
  if (!customerId) return null;
  const scan = await dynamodb
    .scan({
      TableName: USER_PROFILES_TABLE,
      FilterExpression: "stripeCustomerId = :customerId",
      ExpressionAttributeValues: { ":customerId": customerId },
      Limit: 1,
    })
    .promise();
  return scan.Items?.[0]?.userId || null;
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

const resolveStripeSubscription = async ({
  config,
  customerId,
  email,
  subscriptionId,
}) => {
  if (!config?.stripe?.secretKey) return null;
  if (subscriptionId) {
    try {
      const subscription = await stripeGet({
        path: `/v1/subscriptions/${subscriptionId}`,
        secretKey: config.stripe.secretKey,
      });
      let plan =
        subscription.metadata?.plan ||
        subscription.items?.data?.[0]?.price?.id ||
        "";
      const normalizedPlan = normalizePlan(plan, config);
      if (!["starter", "operations", "enterprise"].includes(normalizedPlan)) {
        const priceId = subscription.items?.data?.[0]?.price?.id;
        if (priceId) {
          try {
            const price = await stripeGet({
              path: `/v1/prices/${priceId}`,
              secretKey: config.stripe.secretKey,
            });
            const inferred = inferPlanFromAmount(price?.unit_amount);
            if (inferred) {
              plan = inferred;
            }
          } catch (error) {
            console.warn("Stripe price lookup failed", error);
          }
        }
      }
      return {
        customerId: subscription.customer || customerId || null,
        subscriptionId: subscription.id,
        status: subscription.status,
        plan,
        currentPeriodEnd: subscription.current_period_end
          ? new Date(subscription.current_period_end * 1000).toISOString()
          : null,
      };
    } catch (error) {
      console.warn("Stripe subscription lookup failed", error);
    }
  }
  let resolvedCustomerId = customerId || null;
  if (!resolvedCustomerId && email) {
    const customers = await stripeGet({
      path: `/v1/customers?email=${encodeURIComponent(email)}&limit=5`,
      secretKey: config.stripe.secretKey,
    });
    const list = customers?.data || [];
    if (list.length > 0) {
      resolvedCustomerId = list[0].id;
    }
  }
  if (!resolvedCustomerId) return null;
  const subsResponse = await stripeGet({
    path: `/v1/subscriptions?customer=${encodeURIComponent(
      resolvedCustomerId
    )}&status=all&limit=10`,
    secretKey: config.stripe.secretKey,
  });
    const subscription = pickBestSubscription(subsResponse?.data || []);
  if (!subscription) {
    return { customerId: resolvedCustomerId };
  }
  let plan =
    subscription.metadata?.plan ||
    subscription.items?.data?.[0]?.price?.id ||
    "";
  const normalizedPlan = normalizePlan(plan, config);
  if (!["starter", "operations", "enterprise"].includes(normalizedPlan)) {
    const priceId = subscription.items?.data?.[0]?.price?.id;
    if (priceId) {
      try {
        const price = await stripeGet({
          path: `/v1/prices/${priceId}`,
          secretKey: config.stripe.secretKey,
        });
        const inferred = inferPlanFromAmount(price?.unit_amount);
        if (inferred) {
          plan = inferred;
        }
      } catch (error) {
        console.warn("Stripe price lookup failed", error);
      }
    }
  }
  return {
    customerId: resolvedCustomerId,
    subscriptionId: subscription.id,
    status: subscription.status,
    plan,
    currentPeriodEnd: subscription.current_period_end
      ? new Date(subscription.current_period_end * 1000).toISOString()
      : null,
  };
};

const isAdminUserAsync = async (event) => {
  if (isAdminUser(event)) return true;

  // Fallback 1: check org membership role
  const userId = getUserId(event);
  if (userId && ORG_MEMBERS_TABLE) {
    try {
      const response = await dynamodb
        .scan({
          TableName: ORG_MEMBERS_TABLE,
          FilterExpression:
            "#uid = :uid AND (#role = :admin OR #role = :owner)",
          ExpressionAttributeNames: {
            "#uid": "userId",
            "#role": "role",
          },
          ExpressionAttributeValues: {
            ":uid": userId,
            ":admin": "admin",
            ":owner": "owner",
          },
          ProjectionExpression: "#uid, #role",
          Limit: 1,
        })
        .promise();
      if ((response.Items || []).length > 0) return true;
    } catch (err) {
      console.error("Admin role scan error:", err);
    }
  }

  // Fallback 2: query Cognito group membership directly
  const username =
    event?.requestContext?.authorizer?.jwt?.claims?.["cognito:username"] ||
    event?.requestContext?.authorizer?.jwt?.claims?.username ||
    null;
  if (USER_POOL_ID && username) {
    try {
      const response = await cognito
        .adminListGroupsForUser({
          UserPoolId: USER_POOL_ID,
          Username: username,
        })
        .promise();
      const groups = (response.Groups || []).map((g) => g.GroupName);
      if (groups.includes("Admins")) return true;
    } catch (err) {
      console.error("Admin group lookup error:", err);
    }
  }

  return false;
};

const isAllowedMarketingOrigin = (event) => {
  const origin =
    event?.headers?.origin ||
    event?.headers?.Origin ||
    event?.headers?.referer ||
    event?.headers?.Referer ||
    "";
  if (!origin) return false;
  return (
    origin.includes("rosterchampion.com") ||
    origin.includes("www.rosterchampion.com")
  );
};

const getAdminMetricsData = async () => {
  const totals = {
    users: 0,
    activeSubs: 0,
    trialing: 0,
    inactive: 0,
    active7: 0,
    active30: 0,
  };
  const serviceHealth = {
    api: "ok",
    cognito: "unknown",
    stripe: "unknown",
    lastCheckedAt: new Date().toISOString(),
    secretsError: lastSecretsError || null,
  };
  const authFunnel = {
    attempts: 0,
    success: 0,
    failed: 0,
    googleStart: 0,
    googleSuccess: 0,
    googleFailed: 0,
    offlineSuccess: 0,
  };
  const securityAlerts = {
    failedLogins24h: 0,
    failedLogins7d: 0,
    recentFailed: [],
  };
  const plans = {
    starter: 0,
    operations: 0,
    enterprise: 0,
  };
  const registrationsByDate = {};
  const users = [];
  const admins = [];
  const activityByUser = {};
  const shareSummary = {
    total: 0,
    active: 0,
    revoked: 0,
    expired: 0,
  };
  const shareByUser = {};
  const billingIssues = [];
  const billingAlerts = {
    missingStripeIds: 0,
    expiredActive: 0,
    trialExpired: 0,
    inactiveWithFuturePeriod: 0,
  };
  const websiteMetrics = {
    pageViews7: 0,
    pageViews30: 0,
    uniqueVisitors7: 0,
    uniqueVisitors30: 0,
    topPages: [],
    topCtas: [],
    topDownloads: [],
    dailyPageViews: [],
    recentEvents: [],
  };
  const billingAudit = [];
  const usageTotals = {};
  const usageCosts = {};
  const usageSummary = {
    period: getUsagePeriod(),
    totals: usageTotals,
    costs: usageCosts,
    costTotal: 0,
  };

  if (USER_PROFILES_TABLE) {
    let lastKey;
    do {
      const response = await dynamodb
        .scan({
          TableName: USER_PROFILES_TABLE,
          ProjectionExpression:
            "userId, email, #name, subscriptionStatus, subscriptionPlan, trialStartAt, trialExpiresAt, subscriptionPeriodEnd, stripeCustomerId, stripeSubscriptionId, createdAt, updatedAt",
          ExpressionAttributeNames: {
            "#name": "name",
          },
          ExclusiveStartKey: lastKey,
        })
        .promise();
      const items = response.Items || [];
      for (const item of items) {
        if (item.userId === BILLING_SYSTEM_ID) continue;
        totals.users += 1;
        const status = (item.subscriptionStatus || "").toLowerCase();
        if (status === "active") totals.activeSubs += 1;
        else if (status === "trialing") totals.trialing += 1;
        else if (status) totals.inactive += 1;

        const plan = (item.subscriptionPlan || "").toLowerCase();
        if (plan === "starter") plans.starter += 1;
        if (plan === "operations") plans.operations += 1;
        if (plan === "enterprise") plans.enterprise += 1;

        users.push({
          userId: item.userId,
          email: item.email || "",
          name: item.name || "",
          status: item.subscriptionStatus || "inactive",
          plan: item.subscriptionPlan || "none",
          trialStartAt: item.trialStartAt || null,
          trialExpiresAt: item.trialExpiresAt || null,
          subscriptionPeriodEnd: item.subscriptionPeriodEnd || null,
          createdAt: item.createdAt || null,
          updatedAt: item.updatedAt || null,
        });

        const usage = item.usage || {};
        if (usage.period === usageSummary.period && usage.counts) {
          for (const [key, value] of Object.entries(usage.counts)) {
            const amount = Number(value || 0);
            usageTotals[key] = (usageTotals[key] || 0) + amount;
          }
        }

        const statusLower = (item.subscriptionStatus || "").toLowerCase();
        const periodEndMs = item.subscriptionPeriodEnd
          ? Date.parse(item.subscriptionPeriodEnd)
          : null;
        const trialEndMs = item.trialExpiresAt
          ? Date.parse(item.trialExpiresAt)
          : null;
        const nowMs = Date.now();
        if (
          (statusLower === "active" || statusLower === "trialing") &&
          (!item.stripeCustomerId || !item.stripeSubscriptionId)
        ) {
          billingAlerts.missingStripeIds += 1;
          billingIssues.push({
            userId: item.userId,
            email: item.email || "",
            status: item.subscriptionStatus || "active",
            plan: item.subscriptionPlan || "none",
            reason: "missing_stripe_id",
          });
        }
        if (
          statusLower === "active" &&
          periodEndMs &&
          !Number.isNaN(periodEndMs) &&
          periodEndMs < nowMs
        ) {
          billingAlerts.expiredActive += 1;
          billingIssues.push({
            userId: item.userId,
            email: item.email || "",
            status: item.subscriptionStatus || "active",
            plan: item.subscriptionPlan || "none",
            reason: "period_end_elapsed",
            subscriptionPeriodEnd: item.subscriptionPeriodEnd || null,
          });
        }
        if (
          statusLower === "trialing" &&
          trialEndMs &&
          !Number.isNaN(trialEndMs) &&
          trialEndMs < nowMs
        ) {
          billingAlerts.trialExpired += 1;
          billingIssues.push({
            userId: item.userId,
            email: item.email || "",
            status: item.subscriptionStatus || "trialing",
            plan: item.subscriptionPlan || "none",
            reason: "trial_expired",
            trialExpiresAt: item.trialExpiresAt || null,
          });
        }
        if (
          statusLower === "inactive" &&
          periodEndMs &&
          !Number.isNaN(periodEndMs) &&
          periodEndMs > nowMs
        ) {
          billingAlerts.inactiveWithFuturePeriod += 1;
          billingIssues.push({
            userId: item.userId,
            email: item.email || "",
            status: item.subscriptionStatus || "inactive",
            plan: item.subscriptionPlan || "none",
            reason: "inactive_but_period_active",
            subscriptionPeriodEnd: item.subscriptionPeriodEnd || null,
          });
        }

        const createdAt = item.createdAt ? Date.parse(item.createdAt) : null;
        if (createdAt && !Number.isNaN(createdAt)) {
          const dateKey = new Date(createdAt).toISOString().slice(0, 10);
          registrationsByDate[dateKey] =
            (registrationsByDate[dateKey] || 0) + 1;
        }
      }
      lastKey = response.LastEvaluatedKey;
    } while (lastKey);
  }

  if (USER_POOL_ID) {
    let adminLookupFailed = false;
    let paginationToken = null;
    do {
      try {
        const response = await cognito
          .listUsersInGroup({
            UserPoolId: USER_POOL_ID,
            GroupName: "Admins",
            Limit: 60,
            NextToken: paginationToken || undefined,
          })
          .promise();
        const members = response.Users || [];
        for (const user of members) {
          const emailAttr = (user.Attributes || []).find(
            (attr) => attr.Name === "email"
          );
          admins.push({
            username: user.Username,
            email: emailAttr?.Value || "",
            status: user.UserStatus || "",
          });
        }
        paginationToken = response.NextToken;
      } catch (err) {
        adminLookupFailed = true;
        console.error("Admin group lookup failed", err);
        paginationToken = null;
      }
    } while (paginationToken);
    serviceHealth.cognito = adminLookupFailed ? "error" : "ok";
  } else {
    serviceHealth.cognito = "missing";
  }

  let recentActivity = [];
  if (ANALYTICS_TABLE) {
    try {
      let lastKey;
      const items = [];
      do {
        const response = await dynamodb
          .scan({
            TableName: ANALYTICS_TABLE,
            Limit: 200,
            ExclusiveStartKey: lastKey,
          })
          .promise();
        items.push(...(response.Items || []));
        lastKey = response.LastEvaluatedKey;
      } while (lastKey && items.length < 500);
      items.sort((a, b) => {
        const aTime = Date.parse(a.timestamp || a.createdAt || "") || 0;
        const bTime = Date.parse(b.timestamp || b.createdAt || "") || 0;
        return bTime - aTime;
      });
      for (const item of items) {
        const userId = item.userId || item.user_id;
        if (!userId) continue;
        const ts = item.timestamp || item.createdAt || "";
        const timeValue = Date.parse(ts) || 0;
        if (!activityByUser[userId]) {
          activityByUser[userId] = {
            lastActiveAt: ts || null,
            eventCount: 0,
            platforms: {},
          };
        }
        activityByUser[userId].eventCount += 1;
        const current = Date.parse(activityByUser[userId].lastActiveAt || "") || 0;
        if (timeValue > current) {
          activityByUser[userId].lastActiveAt = ts || null;
        }
        const platform =
          (item.properties && item.properties.platform) || item.platform;
        if (platform) {
          activityByUser[userId].platforms[platform] =
            (activityByUser[userId].platforms[platform] || 0) + 1;
        }
      }

      const now = Date.now();
      const dayMs = 24 * 60 * 60 * 1000;
      const authEvents = items.filter(
        (item) =>
          item.type === "auth" ||
          String(item.name || "").startsWith("auth_")
      );
      for (const item of authEvents) {
        const name = item.name || "";
        const ts = item.timestamp || item.createdAt || "";
        const timeValue = Date.parse(ts) || 0;
        if (name === "auth_attempt") authFunnel.attempts += 1;
        if (name === "auth_success") authFunnel.success += 1;
        if (name === "auth_failed") authFunnel.failed += 1;
        if (name === "auth_google_start") authFunnel.googleStart += 1;
        if (name === "auth_google_success") authFunnel.googleSuccess += 1;
        if (name === "auth_google_failed") authFunnel.googleFailed += 1;
        if (name === "auth_offline_success") authFunnel.offlineSuccess += 1;

        if (name === "auth_failed" && timeValue) {
          if (now - timeValue <= 7 * dayMs) {
            securityAlerts.failedLogins7d += 1;
          }
          if (now - timeValue <= dayMs) {
            securityAlerts.failedLogins24h += 1;
          }
          if (securityAlerts.recentFailed.length < 10) {
            securityAlerts.recentFailed.push({
              userId: item.userId || item.user_id || "",
              timestamp: ts,
              detail: item.properties?.reason || null,
            });
          }
        }
      }

      recentActivity = items.slice(0, 20).map((item) => ({
        name: item.name || item.event || item.type || "event",
        timestamp: item.timestamp || item.createdAt || "",
        userId: item.userId || item.user_id || "",
      }));

      const billingEvents = items
        .filter((item) => item.rosterId === BILLING_AUDIT_ROSTER_ID)
        .slice(0, 20);
      for (const item of billingEvents) {
        billingAudit.push({
          userId: item.userId || item.user_id || "system",
          action: item.name || "billing_event",
          timestamp: item.timestamp || item.createdAt || "",
          status: item.properties?.status || null,
          plan: item.properties?.plan || null,
          source: item.properties?.source || null,
          detail: item.properties?.detail || null,
        });
      }

      const websiteEvents = items.filter((item) => {
        const props = item.properties || {};
        return (
          item.rosterId === "website" ||
          props.source === "website" ||
          props.platform === "website"
        );
      });
      if (websiteEvents.length) {
        const now = Date.now();
        const dayMillis = 24 * 60 * 60 * 1000;
        const viewsByDay = {};
        const pages = {};
        const ctas = {};
        const downloads = {};
        const visitors7 = new Set();
        const visitors30 = new Set();
        for (const event of websiteEvents) {
          const ts = event.timestamp || event.createdAt || "";
          const timeValue = Date.parse(ts) || 0;
          const props = event.properties || {};
          const anonId = props.anonId || event.userId || "anon";
          if (timeValue && now - timeValue <= 30 * dayMillis) {
            visitors30.add(anonId);
          }
          if (timeValue && now - timeValue <= 7 * dayMillis) {
            visitors7.add(anonId);
          }
          const dayKey = ts ? ts.slice(0, 10) : null;
          if (event.name === "page_view" && dayKey) {
            viewsByDay[dayKey] = (viewsByDay[dayKey] || 0) + 1;
            if (timeValue && now - timeValue <= 7 * dayMillis) {
              websiteMetrics.pageViews7 += 1;
            }
            if (timeValue && now - timeValue <= 30 * dayMillis) {
              websiteMetrics.pageViews30 += 1;
            }
            const path = props.path || props.url || "unknown";
            pages[path] = (pages[path] || 0) + 1;
          }
          if (event.name === "cta_click") {
            const label = props.label || props.cta || "cta";
            ctas[label] = (ctas[label] || 0) + 1;
          }
          if (event.name === "download_click") {
            const label = props.label || props.asset || "download";
            downloads[label] = (downloads[label] || 0) + 1;
          }
        }
        websiteMetrics.uniqueVisitors7 = visitors7.size;
        websiteMetrics.uniqueVisitors30 = visitors30.size;
        websiteMetrics.topPages = Object.entries(pages)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 8)
          .map(([path, count]) => ({ path, count }));
        websiteMetrics.topCtas = Object.entries(ctas)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 6)
          .map(([label, count]) => ({ label, count }));
        websiteMetrics.topDownloads = Object.entries(downloads)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 6)
          .map(([label, count]) => ({ label, count }));
        const today = new Date();
        const daily = [];
        for (let i = 29; i >= 0; i -= 1) {
          const date = new Date(
            Date.UTC(
              today.getUTCFullYear(),
              today.getUTCMonth(),
              today.getUTCDate()
            )
          );
          date.setUTCDate(date.getUTCDate() - i);
          const key = date.toISOString().slice(0, 10);
          daily.push({ date: key, count: viewsByDay[key] || 0 });
        }
        websiteMetrics.dailyPageViews = daily;
        websiteMetrics.recentEvents = websiteEvents
          .slice(0, 12)
          .map((event) => ({
            name: event.name || "event",
            timestamp: event.timestamp || event.createdAt || "",
            detail: (event.properties && event.properties.path) || "",
          }));
      }
    } catch (err) {
      console.error("Admin metrics analytics scan failed", err);
    }
  }

  if (SHARE_CODES_TABLE) {
    let lastKey;
    const now = Date.now();
    do {
      const response = await dynamodb
        .scan({
          TableName: SHARE_CODES_TABLE,
          ProjectionExpression:
            "code, createdBy, createdAt, expiresAt, maxUses, uses, #status, rosterId",
          ExpressionAttributeNames: {
            "#status": "status",
          },
          ExclusiveStartKey: lastKey,
        })
        .promise();
      const items = response.Items || [];
      for (const item of items) {
        shareSummary.total += 1;
        const statusRaw = (item.status || "active").toString().toLowerCase();
        const expired =
          item.expiresAt && Date.parse(item.expiresAt) < now;
        if (statusRaw === "revoked") {
          shareSummary.revoked += 1;
        } else if (expired) {
          shareSummary.expired += 1;
        } else {
          shareSummary.active += 1;
        }
        const owner = item.createdBy || "unknown";
        if (!shareByUser[owner]) {
          shareByUser[owner] = {
            total: 0,
            active: 0,
            revoked: 0,
            expired: 0,
          };
        }
        shareByUser[owner].total += 1;
        if (statusRaw === "revoked") {
          shareByUser[owner].revoked += 1;
        } else if (expired) {
          shareByUser[owner].expired += 1;
        } else {
          shareByUser[owner].active += 1;
        }
      }
      lastKey = response.LastEvaluatedKey;
    } while (lastKey);
  }

  const today = new Date();
  const registrationTrends = [];
  for (let i = 29; i >= 0; i -= 1) {
    const date = new Date(
      Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate())
    );
    date.setUTCDate(date.getUTCDate() - i);
    const key = date.toISOString().slice(0, 10);
    registrationTrends.push({
      date: key,
      count: registrationsByDate[key] || 0,
    });
  }

  const now = Date.now();
  const trialEndingSoon = users
    .filter((u) => {
      if (!u.trialExpiresAt) return false;
      const expires = Date.parse(u.trialExpiresAt);
      if (Number.isNaN(expires)) return false;
      return expires > now && expires <= now + 3 * 24 * 60 * 60 * 1000;
    })
    .sort((a, b) => Date.parse(a.trialExpiresAt) - Date.parse(b.trialExpiresAt))
    .slice(0, 20);

  for (const user of users) {
    const activity = activityByUser[user.userId];
    if (activity) {
      user.lastActiveAt = activity.lastActiveAt;
      user.eventCount = activity.eventCount;
      user.platforms = Object.keys(activity.platforms || {});
      const lastActiveMs = activity.lastActiveAt
        ? Date.parse(activity.lastActiveAt)
        : null;
      if (lastActiveMs) {
        const diffDays = Math.floor(
          (Date.now() - lastActiveMs) / (24 * 60 * 60 * 1000)
        );
        if (diffDays <= 7) totals.active7 += 1;
        if (diffDays <= 30) totals.active30 += 1;
      }
    }
    const shareCounts = shareByUser[user.userId];
    if (shareCounts) {
      user.shareCodesTotal = shareCounts.total;
      user.shareCodesActive = shareCounts.active;
      user.shareCodesRevoked = shareCounts.revoked;
      user.shareCodesExpired = shareCounts.expired;
    }
  }

  const billingHealth = await getBillingSystemRecord();
  let runtimeConfig = null;
  try {
    runtimeConfig = await getRuntimeConfig();
    serviceHealth.stripe = runtimeConfig?.stripe?.secretKey ? "ok" : "missing";
  } catch (err) {
    serviceHealth.stripe = "error";
  }
  if (runtimeConfig) {
    for (const key of Object.keys(usageTotals)) {
      const rate = getUsageCostRate(key, runtimeConfig);
      const cost = rate * (usageTotals[key] || 0);
      usageCosts[key] = Number(cost.toFixed(4));
    }
    usageSummary.costTotal = Number(
      Object.values(usageCosts)
        .reduce((sum, val) => sum + (val || 0), 0)
        .toFixed(4)
    );
  }
  const costAlerts = [];
  const budget = Number(runtimeConfig?.costBudget?.monthlyUsd || 0);
  const thresholds = Array.isArray(runtimeConfig?.costBudget?.thresholds)
    ? runtimeConfig.costBudget.thresholds
    : [];
  if (budget > 0 && usageSummary.costTotal > 0) {
    thresholds.forEach((ratio) => {
      const limit = budget * Number(ratio || 0);
      if (limit && usageSummary.costTotal >= limit) {
        costAlerts.push({
          level: ratio >= 1 ? "critical" : "warning",
          threshold: ratio,
          budget,
          estimatedSpend: usageSummary.costTotal,
          message: `Estimated spend $${usageSummary.costTotal} exceeds ${
            ratio * 100
          }% of $${budget} budget.`,
        });
      }
    });
  }
  const billingStatus = {
    active: totals.activeSubs,
    trialing: totals.trialing,
    inactive: totals.inactive,
    totalUsers: totals.users,
    lastWebhookAt: billingHealth?.lastWebhookAt || null,
    lastReconcileAt: billingHealth?.lastReconcileAt || null,
  };

  return {
    totals,
    plans,
    recentActivity,
    registrationTrends,
    users,
    admins,
    trialEndingSoon,
    shareSummary,
    serviceHealth,
    authFunnel,
    securityAlerts,
    websiteMetrics,
    billingHealth,
    billingStatus,
    billingAlerts,
    billingIssues,
    billingAudit,
    usageSummary,
    usageQuotas: runtimeConfig?.usageQuotas || {},
    usageCosts: runtimeConfig?.usageCosts || {},
    usageHardCaps: runtimeConfig?.usageHardCaps || {},
    costBudget: runtimeConfig?.costBudget || {},
    costAlerts,
  };
};

const hashPassword = (password) => {
  if (!password) return null;
  return crypto
    .createHash("sha256")
    .update(`${ROSTER_SALT}:${password}`)
    .digest("hex");
};

const roleRank = (role) => {
  switch (role) {
    case "owner":
      return 4;
    case "admin":
      return 3;
    case "manager":
      return 2;
    case "editor":
    case "member":
    case "staff":
      return 1;
    case "viewer":
      return 0;
    default:
      return 0;
  }
};

const ensureRosterAccess = async (rosterId, userId) => {
  if (!rosterId || !userId) return false;
  const membership = await dynamodb
    .get({
      TableName: ROSTER_MEMBERS_TABLE,
      Key: { rosterId, userId },
    })
    .promise();
  return Boolean(membership.Item);
};

const getUserProfile = async (userId) => {
  if (!userId) return null;
  const profile = await dynamodb
    .get({
      TableName: USER_PROFILES_TABLE,
      Key: { userId },
    })
    .promise();
  return profile.Item || null;
};

const BILLING_SYSTEM_ID = "system#billing";

const getBillingSystemRecord = async () => {
  if (!USER_PROFILES_TABLE) return null;
  const record = await dynamodb
    .get({
      TableName: USER_PROFILES_TABLE,
      Key: { userId: BILLING_SYSTEM_ID },
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
      Key: { userId: BILLING_SYSTEM_ID },
      UpdateExpression: `SET ${expression.join(", ")}`,
      ExpressionAttributeNames: Object.keys(names).length ? names : undefined,
      ExpressionAttributeValues: values,
    })
    .promise();
};

const findProfileByEmail = async (emailLower, emailRaw) => {
  let lastKey = null;
  do {
    const response = await dynamodb
      .scan({
        TableName: USER_PROFILES_TABLE,
        FilterExpression: "#email = :emailRaw OR #emailLower = :emailLower",
        ExpressionAttributeNames: {
          "#email": "email",
          "#emailLower": "emailLower",
        },
        ExpressionAttributeValues: {
          ":emailRaw": emailRaw,
          ":emailLower": emailLower,
        },
        ProjectionExpression:
          "userId, email, subscriptionStatus, subscriptionPlan, trialStartAt, trialExpiresAt, updatedAt",
        ExclusiveStartKey: lastKey || undefined,
      })
      .promise();
    if (response.Items && response.Items.length > 0) {
      return response.Items[0];
    }
    lastKey = response.LastEvaluatedKey || null;
  } while (lastKey);
  return null;
};

const getTrialHistoryRecord = async (emailLower) => {
  if (!TRIAL_HISTORY_TABLE) return null;
  const normalized = (emailLower || "").toLowerCase().trim();
  if (!normalized) return null;
  try {
    const response = await dynamodb
      .get({
        TableName: TRIAL_HISTORY_TABLE,
        Key: { emailLower: normalized },
      })
      .promise();
    return response.Item || null;
  } catch (err) {
    console.warn("Trial history lookup failed", err);
    return null;
  }
};

const recordTrialHistory = async ({ emailLower, email, userId, source }) => {
  if (!TRIAL_HISTORY_TABLE) return;
  const normalized = (emailLower || "").toLowerCase().trim();
  if (!normalized) return;
  try {
    await dynamodb
      .put({
        TableName: TRIAL_HISTORY_TABLE,
        Item: {
          emailLower: normalized,
          email: email || "",
          userId: userId || "",
          firstTrialAt: new Date().toISOString(),
          source: source || "unknown",
        },
        ConditionExpression: "attribute_not_exists(emailLower)",
      })
      .promise();
  } catch (err) {
    if (err.code !== "ConditionalCheckFailedException") {
      console.warn("Trial history record failed", err);
    }
  }
};

const ensureUserProfile = async (userId, email = "") => {
  if (!userId) return null;
  const existing = await getUserProfile(userId);
  if (existing) return existing;
  const normalizedEmail = (email || "").toLowerCase().trim();
  if (normalizedEmail) {
    const prior = await findProfileByEmail(normalizedEmail, email);
    const history = await getTrialHistoryRecord(normalizedEmail);
    if ((prior && prior.trialStartAt) || history) {
      const now = new Date().toISOString();
      const usagePeriod = getUsagePeriod();
      const item = {
        userId,
        email: email ?? "",
        emailLower: normalizedEmail,
        subscriptionStatus: "inactive",
        subscriptionPlan: "none",
        createdAt: now,
        updatedAt: now,
        usage: { period: usagePeriod, counts: {} },
      };
      await dynamodb
        .put({
          TableName: USER_PROFILES_TABLE,
          Item: item,
        })
        .promise();
      return item;
    }
  }
  const now = new Date();
  const trialStartAt = now.toISOString();
  const trialExpiresAt = new Date(
    now.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();
  const createdAt = trialStartAt;
  const usagePeriod = getUsagePeriod();
  const item = {
    userId,
    email: email ?? "",
    emailLower: normalizedEmail || (email || "").toLowerCase(),
    subscriptionStatus: "trialing",
    subscriptionPlan: "trial",
    trialStartAt,
    trialExpiresAt,
    createdAt,
    updatedAt: createdAt,
    usage: { period: usagePeriod, counts: {} },
  };
  await dynamodb
    .put({
      TableName: USER_PROFILES_TABLE,
      Item: item,
    })
    .promise();
  if (normalizedEmail) {
    await recordTrialHistory({
      emailLower: normalizedEmail,
      email,
      userId,
      source: "ensureUserProfile",
    });
  }
  return item;
};

const GRACE_DAYS = 7;
const TRIAL_DAYS = 7;

const isWithinGrace = (profile) => {
  if (!profile) return false;
  const status = (profile.subscriptionStatus || "").toLowerCase();
  if (status === "active") return true;
  const graceEligible = ["past_due", "unpaid", "canceled"];
  if (!graceEligible.includes(status)) return false;
  const now = Date.now();
  const periodEnd = profile.subscriptionPeriodEnd
    ? Date.parse(profile.subscriptionPeriodEnd)
    : null;
  const updatedAt = profile.updatedAt ? Date.parse(profile.updatedAt) : null;
  const reference = periodEnd || updatedAt;
  if (!reference || Number.isNaN(reference)) return false;
  const graceMillis = GRACE_DAYS * 24 * 60 * 60 * 1000;
  return now - reference <= graceMillis;
};

const getTrialState = (profile) => {
  if (!profile) return { active: false };
  const start = profile.trialStartAt ? Date.parse(profile.trialStartAt) : null;
  if (!start || Number.isNaN(start)) return { active: false };
  const end =
    profile.trialExpiresAt && !Number.isNaN(Date.parse(profile.trialExpiresAt))
      ? Date.parse(profile.trialExpiresAt)
      : start + TRIAL_DAYS * 24 * 60 * 60 * 1000;
  const now = Date.now();
  return {
    active: now <= end,
    startAt: new Date(start).toISOString(),
    expiresAt: new Date(end).toISOString(),
  };
};

const ensureActiveSubscription = async (userId) => {
  const profile = await ensureUserProfile(userId);
  const trial = getTrialState(profile);
  if (trial.active) return true;
  return isWithinGrace(profile);
};

const normalizePlan = (plan, config) => {
  if (!plan) return "";
  const normalized = plan.toString().toLowerCase();
  if (["starter", "operations", "enterprise"].includes(normalized)) {
    return normalized;
  }
  const prices = config?.stripe?.prices || {};
  if (normalized === (prices.starter || "").toLowerCase()) return "starter";
  if (normalized === (prices.operations || "").toLowerCase()) return "operations";
  if (normalized === (prices.enterprise || "").toLowerCase()) return "enterprise";
  return normalized;
};

const inferPlanFromAmount = (amount) => {
  if (!amount) return "";
  if (amount === 900 || amount === 9) return "starter";
  if (amount === 2900 || amount === 29) return "operations";
  if (amount === 7900 || amount === 79) return "enterprise";
  return "";
};

const planRank = (plan) => {
  switch (plan) {
    case "enterprise":
      return 3;
    case "operations":
      return 2;
    case "starter":
      return 1;
    default:
      return 0;
  }
};

const sharePlanLimits = (plan) => {
  switch (plan) {
    case "enterprise":
      return { maxUses: 100, maxMonths: 36 };
    case "operations":
      return { maxUses: 25, maxMonths: 24 };
    case "starter":
      return { maxUses: 16, maxMonths: 16 };
    default:
      return { maxUses: 0, maxMonths: 0 };
  }
};

const monthsToHours = (months) => Math.round(months * 30 * 24);

const getUsagePeriod = () => new Date().toISOString().slice(0, 7);

const defaultUsageQuotas = {
  starter: {
    ai: 120,
    exports: 60,
    timeclock: 60,
    share_create: 12,
    share_access: 500,
    share_leave: 120,
    analytics: 2000,
  },
  operations: {
    ai: 1200,
    exports: 240,
    timeclock: 240,
    share_create: 60,
    share_access: 5000,
    share_leave: 600,
    analytics: 20000,
  },
  enterprise: {
    ai: 12000,
    exports: 1200,
    timeclock: 1200,
    share_create: 600,
    share_access: 50000,
    share_leave: 6000,
    analytics: 200000,
  },
};

const defaultUsageCosts = {
  ai: 0.002,
  exports: 0.001,
  timeclock: 0.0005,
  share_create: 0.0002,
  share_access: 0.00001,
  share_leave: 0.0003,
  analytics: 0.000001,
};

const getPlanQuota = (plan, key, config) => {
  const overrides = config?.usageQuotas || {};
  const planQuotas = overrides?.[plan] || defaultUsageQuotas[plan] || {};
  const limit = planQuotas?.[key];
  if (limit === null || limit === undefined) return Infinity;
  return Number(limit);
};

const getUsageCostRate = (key, config) => {
  const overrides = config?.usageCosts || {};
  const rate = overrides?.[key];
  if (rate === null || rate === undefined) {
    return defaultUsageCosts[key] ?? 0;
  }
  return Number(rate) || 0;
};

const getHardQuotaLimit = (key, config) => {
  const hardCaps = config?.usageHardCaps || {};
  const limit = hardCaps?.[key];
  if (limit === null || limit === undefined) return Infinity;
  return Number(limit);
};

const buildUsageSnapshot = (profile, config) => {
  const period = getUsagePeriod();
  const trial = getTrialState(profile);
  const plan = trial.active
    ? "enterprise"
    : normalizePlan(profile?.subscriptionPlan || "", config) || "starter";
  const usage = profile?.usage || {};
  const counts = usage.period === period ? usage.counts || {} : {};
  const limits = {};
  const remaining = {};
  [
    "ai",
    "exports",
    "timeclock",
    "share_create",
    "share_access",
    "share_leave",
    "analytics",
  ].forEach((key) => {
    const limit = getPlanQuota(plan, key, config);
    limits[key] = Number.isFinite(limit) ? limit : null;
    const used = counts[key] || 0;
    remaining[key] = Number.isFinite(limit) ? Math.max(0, limit - used) : null;
  });
  return { period, plan, counts, limits, remaining };
};

const consumeQuota = async ({ userId, key, amount = 1, config }) => {
  const profile = await ensureUserProfile(userId);
  const period = getUsagePeriod();
  const plan = normalizePlan(profile?.subscriptionPlan || "", config) || "starter";
  const baseLimit = getPlanQuota(plan, key, config);
  const hardLimit = getHardQuotaLimit(key, config);
  const userLimitRaw = profile?.usageLimits?.[key];
  const userLimit =
    userLimitRaw === null || userLimitRaw === undefined
      ? Infinity
      : Number(userLimitRaw);
  const limit = Math.min(baseLimit, hardLimit, userLimit);
  if (!Number.isFinite(limit)) {
    return { allowed: true, remaining: null, limit: null, period, plan };
  }
  const usage = profile?.usage || {};
  const counts = usage.period === period ? { ...(usage.counts || {}) } : {};
  const used = counts[key] || 0;
  if (used + amount > limit) {
    return { allowed: false, remaining: Math.max(0, limit - used), limit, period, plan };
  }
  counts[key] = used + amount;
  const now = new Date().toISOString();
  await dynamodb
    .update({
      TableName: USER_PROFILES_TABLE,
      Key: { userId },
      UpdateExpression: "SET #usage = :usage, #updatedAt = :updatedAt",
      ExpressionAttributeNames: {
        "#usage": "usage",
        "#updatedAt": "updatedAt",
      },
      ExpressionAttributeValues: {
        ":usage": { period, counts },
        ":updatedAt": now,
      },
    })
    .promise();
  return {
    allowed: true,
    remaining: Math.max(0, limit - counts[key]),
    limit,
    period,
    plan,
  };
};

const ensurePlanAccess = async (userId, requiredPlan) => {
  const profile = await ensureUserProfile(userId);
  const trial = getTrialState(profile);
  if (trial.active) return true;
  if (!isWithinGrace(profile)) return false;
  const config = await getRuntimeConfig();
  const userPlan = normalizePlan(profile?.subscriptionPlan || "", config);
  return planRank(userPlan) >= planRank(requiredPlan);
};

const ensurePaidPlanAccess = async (userId, requiredPlan) => {
  const profile = await ensureUserProfile(userId);
  if (!isWithinGrace(profile)) return false;
  const config = await getRuntimeConfig();
  const userPlan = normalizePlan(profile?.subscriptionPlan || "", config);
  if (!userPlan || userPlan === "none" || userPlan === "trial") return false;
  return planRank(userPlan) >= planRank(requiredPlan);
};

const ensureRosterRole = async (rosterId, userId, requiredRole) => {
  const membership = await dynamodb
    .get({
      TableName: ROSTER_MEMBERS_TABLE,
      Key: { rosterId, userId },
    })
    .promise();
  if (!membership.Item) return false;
  const memberRole = membership.Item.role || "staff";
  return roleRank(memberRole) >= roleRank(requiredRole);
};

const ensureOrgRole = async (orgId, userId, requiredRole) => {
  const membership = await dynamodb
    .get({
      TableName: ORG_MEMBERS_TABLE,
      Key: { orgId, userId },
    })
    .promise();
  if (!membership.Item) return false;
  const memberRole = membership.Item.role || "staff";
  return roleRank(memberRole) >= roleRank(requiredRole);
};

const writeAuditLog = async ({
  rosterId,
  userId,
  action,
  metadata = {},
  timestamp,
}) => {
  if (!AUDIT_LOGS_TABLE || !rosterId) return;
  const now = timestamp || new Date().toISOString();
  const logId = `${Date.now()}_${userId || "system"}`;
  await dynamodb
    .put({
      TableName: AUDIT_LOGS_TABLE,
      Item: {
        rosterId,
        logId,
        user_id: userId || "system",
        action,
        metadata,
        timestamp: now,
      },
    })
    .promise();
};

const BILLING_AUDIT_ROSTER_ID = "billing";

const writeBillingAudit = async ({
  userId,
  action,
  status,
  plan,
  source,
  detail,
}) => {
  if (!ANALYTICS_TABLE) return;
  const event = {
    rosterId: BILLING_AUDIT_ROSTER_ID,
    eventId: `${Date.now()}_${crypto.randomBytes(4).toString("hex")}`,
    userId: userId || "system",
    name: action || "billing_event",
    type: "billing",
    timestamp: new Date().toISOString(),
    sessionId: null,
    properties: {
      status: status || null,
      plan: plan || null,
      source: source || "system",
      detail: detail || "",
    },
  };
  try {
    await dynamodb
      .put({
        TableName: ANALYTICS_TABLE,
        Item: event,
      })
      .promise();
  } catch (err) {
    console.error("Billing audit put error:", err);
  }
};

const writeAnalyticsEvents = async (events) => {
  if (!ANALYTICS_TABLE || events.length === 0) return 0;
  let accepted = 0;
  for (const event of events) {
    try {
      await dynamodb
        .put({
          TableName: ANALYTICS_TABLE,
          Item: event,
        })
        .promise();
      accepted += 1;
    } catch (err) {
      console.error("Analytics put error:", err);
    }
  }
  return accepted;
};

const generateShareCode = (length = 8) => {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.randomBytes(length);
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars[bytes[i] % chars.length];
  }
  return code;
};

const normalizeShareCode = (value) => {
  if (!value || typeof value !== "string") return null;
  const cleaned = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (!/^[A-Z2-9]{6,12}$/.test(cleaned)) return null;
  return cleaned;
};

const suggestShareCodes = (base, count = 3) => {
  const prefix = (base || "").replace(/[^A-Z2-9]/g, "").slice(0, 4);
  const suggestions = new Set();
  while (suggestions.size < count) {
    suggestions.add(`${prefix}${generateShareCode(4)}`);
  }
  return Array.from(suggestions);
};

const loadShareCode = async (code) => {
  if (!code || !SHARE_CODES_TABLE) return null;
  const record = await dynamodb
    .get({
      TableName: SHARE_CODES_TABLE,
      Key: { code },
    })
    .promise();
  return record.Item || null;
};

const validateShareCode = (share) => {
  if (!share) return { ok: false, status: 404, error: "Share code not found" };
  if (share.status === "revoked") {
    return { ok: false, status: 410, error: "Share code revoked" };
  }
  if (share.expiresAt && new Date(share.expiresAt) < new Date()) {
    return { ok: false, status: 410, error: "Share code expired" };
  }
  if (
    share.maxUses != null &&
    typeof share.uses === "number" &&
    share.uses >= share.maxUses
  ) {
    return { ok: false, status: 410, error: "Share code exhausted" };
  }
  return { ok: true };
};

const incrementShareUses = async (share) => {
  if (!SHARE_CODES_TABLE) return false;
  const updateParams = {
    TableName: SHARE_CODES_TABLE,
    Key: { code: share.code },
    UpdateExpression: "SET #uses = if_not_exists(#uses, :zero) + :inc",
    ExpressionAttributeNames: { "#uses": "uses" },
    ExpressionAttributeValues: { ":zero": 0, ":inc": 1 },
  };

  if (share.maxUses != null) {
    updateParams.ConditionExpression =
      "attribute_not_exists(#uses) OR #uses < :maxUses";
    updateParams.ExpressionAttributeValues[":maxUses"] = share.maxUses;
  }

  try {
    await dynamodb.update(updateParams).promise();
    return true;
  } catch (error) {
    if (error.code === "ConditionalCheckFailedException") {
      return false;
    }
    throw error;
  }
};

const revokeShareCodes = async ({
  userId,
  rosterId,
  keepNewestCount = 0,
  reason = "admin_action",
}) => {
  if (!userId || !SHARE_CODES_TABLE) return 0;
  const items = await listShareCodesForUser({ userId, rosterId });
  const active = items.filter((item) => (item.status || "active") === "active");
  if (active.length === 0) return 0;
  const sorted = active.sort((a, b) =>
    (b.createdAt || "").localeCompare(a.createdAt || "")
  );
  const toRevoke = sorted.slice(Math.max(0, keepNewestCount));
  if (toRevoke.length === 0) return 0;
  const now = new Date().toISOString();
  for (const share of toRevoke) {
    await dynamodb
      .update({
        TableName: SHARE_CODES_TABLE,
        Key: { code: share.code },
        UpdateExpression:
          "SET #status = :status, revokedAt = :revokedAt, revokedBy = :revokedBy, revokeReason = :reason",
        ExpressionAttributeNames: { "#status": "status" },
        ExpressionAttributeValues: {
          ":status": "revoked",
          ":revokedAt": now,
          ":revokedBy": userId,
          ":reason": reason,
        },
      })
      .promise();
  }
  return toRevoke.length;
};

const listShareCodesForUser = async ({ userId, rosterId }) => {
  if (!userId || !SHARE_CODES_TABLE) return [];
  const params = {
    TableName: SHARE_CODES_TABLE,
    FilterExpression: "#createdBy = :createdBy",
    ExpressionAttributeNames: {
      "#createdBy": "createdBy",
    },
    ExpressionAttributeValues: {
      ":createdBy": userId,
    },
  };
  if (rosterId) {
    params.FilterExpression =
      "#createdBy = :createdBy AND #rosterId = :rosterId";
    params.ExpressionAttributeNames["#rosterId"] = "rosterId";
    params.ExpressionAttributeValues[":rosterId"] = rosterId;
  }
  let items = [];
  let lastKey;
  do {
    const response = await dynamodb
      .scan({ ...params, ExclusiveStartKey: lastKey })
      .promise();
    items = items.concat(response.Items || []);
    lastKey = response.LastEvaluatedKey;
  } while (lastKey);
  return items;
};

const publishNotification = async ({ subject, message }) => {
  if (!SNS_TOPIC_ARN) return;
  await sns
    .publish({
      TopicArn: SNS_TOPIC_ARN,
      Subject: subject,
      Message: JSON.stringify(message, null, 2),
    })
    .promise();
};

const sendEmail = async ({ to, subject, body, replyTo }) => {
  const config = await getRuntimeConfig();
  if (!config.sesFrom || !to) return;
  await ses
    .sendEmail({
      Source: config.sesFrom,
      Destination: { ToAddresses: [to] },
      ReplyToAddresses: replyTo ? [replyTo] : undefined,
      Message: {
        Subject: { Data: subject },
        Body: { Text: { Data: body } },
      },
    })
    .promise();
};

const buildAiSystemPrompt = () => `You are an expert roster optimization assistant.
Return ONLY valid JSON. Do not include markdown, code fences, or commentary.
Schema:
{"suggestions":[{"id":"string","title":"string","description":"string","reason":"string","priority":0-3,"type":0-5,"actionType":0-6,"actionPayload":object,"impactScore":0-1,"confidence":0-1,"affectedStaff":["string"],"metrics":object}]}
Rules:
- Use only names from staff in the input; do not invent people.
- Use shifts exactly as provided in the pattern or overrides (e.g., "D","N","OFF","L").
- If no good suggestions, return {"suggestions":[]}.
- Keep suggestions under 6 items and focused on conflicts, coverage gaps, leave conflicts, fairness, workload, and policy violations in policySummary.
Enum mapping:
priority: 0=low,1=medium,2=high,3=critical
type: 0=workload,1=pattern,2=leave,3=coverage,4=fairness,5=other
actionType: 0=setOverride,1=swapShifts,2=addEvent,3=changeStaffStatus,4=adjustLeave,5=updatePattern,6=none
Action payload shapes:
- setOverride: {"personName":"string","date":"ISO8601","shift":"string","reason":"string"}
- swapShifts: {"personA":"string","personB":"string","date":"ISO8601","shiftA":"string?","shiftB":"string?"}
- addEvent: {"title":"string","description":"string?","date":"ISO8601","eventType":0-7,"affectedStaff":["string"],"recurringId":"string?"}
- changeStaffStatus: {"personName":"string","isActive":true/false}
- adjustLeave: {"personName":"string","delta":number}
- updatePattern: {"week":number,"day":number,"shift":"string"}
If actionType is 6 (none), omit actionPayload.`;

const buildAiUserPrompt = ({
  staff,
  overrides,
  pattern,
  events,
  constraints,
  healthScore,
  policySummary,
}) => {
  const payload = {
    staff,
    overrides,
    pattern,
    events,
    constraints,
    healthScore,
    policySummary,
  };
  return `Analyze this roster data and return optimization suggestions.\nInput JSON:\n${JSON.stringify(
    payload
  )}`;
};

const safeJsonParse = (text) => {
  if (!text || typeof text !== "string") return null;
  try {
    return JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) return null;
    try {
      return JSON.parse(text.slice(start, end + 1));
    } catch {
      return null;
    }
  }
};

const invokeBedrock = async (body) => {
  const config = await getRuntimeConfig();
  const modelId = config.bedrockModelId;
  const response = await bedrock
    .invokeModel({
      modelId,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify({
        anthropic_version: "bedrock-2023-05-31",
        max_tokens: 900,
        temperature: 0.3,
        system: buildAiSystemPrompt(),
        messages: [
          {
            role: "user",
            content: [{ type: "text", text: buildAiUserPrompt(body) }],
          },
        ],
      }),
    })
    .promise();

  const decoded = JSON.parse(Buffer.from(response.body).toString("utf-8"));
  const text = Array.isArray(decoded.content)
    ? decoded.content.map((c) => c.text).join("")
    : decoded.completion || "";
  return safeJsonParse(text);
};

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const batchDelete = async (tableName, keys) => {
  if (!keys.length) return;
  const chunks = [];
  for (let i = 0; i < keys.length; i += 25) {
    chunks.push(keys.slice(i, i + 25));
  }
  for (const chunk of chunks) {
    let requestItems = chunk.map((key) => ({
      DeleteRequest: { Key: key },
    }));
    let attempts = 0;
    while (requestItems.length) {
      const response = await dynamodb
        .batchWrite({
          RequestItems: { [tableName]: requestItems },
        })
        .promise();
      const unprocessed = response.UnprocessedItems?.[tableName] || [];
      if (!unprocessed.length) break;
      attempts += 1;
      if (attempts >= 5) {
        throw new Error(
          `Failed to delete all items from ${tableName} after ${attempts} attempts`
        );
      }
      requestItems = unprocessed;
      await wait(100 * attempts);
    }
  }
};

const deleteByUserIdIndex = async ({ tableName, userId }) => {
  const query = await dynamodb
    .query({
      TableName: tableName,
      IndexName: "userId-index",
      KeyConditionExpression: "userId = :userId",
      ExpressionAttributeValues: { ":userId": userId },
    })
    .promise();
  return query.Items || [];
};

const chunkArray = (items, size) => {
  const chunks = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
};

exports.handler = async (event) => {
    const rawPath = event.rawPath || event.path || "/";
    const stage = event.requestContext?.stage;
    let path = rawPath;
  if (stage && path.startsWith(`/${stage}/`)) {
    path = path.slice(stage.length + 1);
  } else if (stage && path === `/${stage}`) {
    path = "/";
  }
    const method = event.requestContext?.http?.method || event.httpMethod;

    if (method === "OPTIONS") {
      return {
        statusCode: 200,
        headers: { "content-type": "application/json", ...corsHeaders },
        body: "",
      };
    }

  const openRoutes = new Set([
    "/health",
    "/app/version",
    "/share/access",
    "/share/leave",
    "/share/request",
    "/share/validate",
    "/billing/webhook",
    "/billing/fx",
  ]);
  if (path === "/health") {
    return jsonResponse(200, { ok: true });
  }

  if (method === "GET" && path === "/app/version") {
    const platform = (event.queryStringParameters?.platform || "").toLowerCase();
    const config = await getRuntimeConfig();
    const minVersion = config.minVersions[platform] || config.minVersions.default;
    const latestVersion =
      config.latestVersions[platform] || config.latestVersions.default;
    const updateUrl = config.updateUrls[platform] || config.updateUrls.default;
    return jsonResponse(200, {
      minVersion,
      latestVersion,
      updateUrl,
    });
  }

  if (method === "GET" && path === "/billing/fx") {
    try {
      const rates = await getFxRatesCached();
      return jsonResponse(200, rates);
    } catch (error) {
      console.error("FX rates error", error);
      return jsonResponse(500, { error: "Unable to load FX rates" });
    }
  }

  if (method === "GET" && path === "/app/update") {
    const platform = (event.queryStringParameters?.platform || "").toLowerCase();
    const config = await getRuntimeConfig();
    const bucket = process.env.UPDATE_BUCKET;
    const manifestKey = process.env.UPDATE_MANIFEST_KEY;

    let manifest = null;
    if (bucket && manifestKey) {
      try {
        const obj = await s3
          .getObject({ Bucket: bucket, Key: manifestKey })
          .promise();
        if (obj.Body) {
          manifest = JSON.parse(obj.Body.toString("utf-8"));
        }
      } catch (e) {
        // Ignore manifest load errors, fallback to env values
      }
    }

    const manifestMin = manifest?.minVersion;
    const manifestLatest = manifest?.latestVersion?.[platform];
    const manifestKeyForPlatform = manifest?.files?.[platform];
    const manifestUpdateUrl = manifest?.updatePage;

    const minVersion =
      manifestMin ||
      config.minVersions[platform] ||
      config.minVersions.default ||
      "";
    const latestVersion =
      manifestLatest ||
      config.latestVersions[platform] ||
      config.latestVersions.default ||
      "";

    let updateUrl =
      manifestUpdateUrl ||
      config.updateUrls[platform] ||
      config.updateUrls.default ||
      "";

    if (bucket && manifestKeyForPlatform) {
      try {
        const signed = s3.getSignedUrl("getObject", {
          Bucket: bucket,
          Key: manifestKeyForPlatform,
          Expires: 900,
        });
        updateUrl = signed;
      } catch (_) {}
    }

    return jsonResponse(200, {
      minVersion,
      latestVersion,
      updateUrl,
      platform,
      manifestKey: manifestKey || null,
    });
  }

  const userId = getUserId(event);
  if (!openRoutes.has(path) && !userId) {
    return jsonResponse(401, { error: "Unauthorized" });
  }

  if (method === "POST" && path === "/rosters/create") {
    const { name, password, orgId } = parseBody(event);
    if (!name) return jsonResponse(400, { error: "Missing roster name" });
    if (orgId) {
      const canCreate = await ensureOrgRole(orgId, userId, "manager");
      if (!canCreate) {
        return jsonResponse(403, { error: "Forbidden" });
      }
    }
    const rosterId = Date.now().toString();
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: ROSTERS_TABLE,
        Item: {
          rosterId,
          name,
          ownerId: userId,
          orgId: orgId ?? null,
          passwordHash: hashPassword(password),
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();
    await dynamodb
      .put({
        TableName: ROSTER_MEMBERS_TABLE,
        Item: {
          rosterId,
          userId,
          role: "owner",
          joinedAt: now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_created",
      metadata: { name, orgId: orgId ?? null },
      timestamp: now,
    });
    return jsonResponse(200, { rosterId });
  }

  if (method === "POST" && path === "/rosters/join") {
    const { rosterId, password } = parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const roster = await dynamodb
      .get({ TableName: ROSTERS_TABLE, Key: { rosterId } })
      .promise();
    if (!roster.Item) {
      return jsonResponse(404, { error: "Roster not found" });
    }
    const hash = hashPassword(password);
    if (roster.Item.passwordHash && roster.Item.passwordHash !== hash) {
      return jsonResponse(403, { error: "Invalid roster password" });
    }
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (isMember) {
      return jsonResponse(200, { rosterId });
    }
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: ROSTER_MEMBERS_TABLE,
        Item: {
          rosterId,
          userId,
          role: "member",
          joinedAt: now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_joined",
      metadata: {},
      timestamp: now,
    });
    return jsonResponse(200, { rosterId });
  }

  if (method === "GET" && path === "/rosters") {
    const memberships = await dynamodb
      .query({
        TableName: ROSTER_MEMBERS_TABLE,
        IndexName: "userId-index",
        KeyConditionExpression: "userId = :userId",
        ExpressionAttributeValues: { ":userId": userId },
      })
      .promise();
    const rosterIds = memberships.Items.map((m) => m.rosterId);
    if (rosterIds.length === 0) return jsonResponse(200, []);

    const batch = {
      RequestItems: {
        [ROSTERS_TABLE]: {
          Keys: rosterIds.map((id) => ({ rosterId: id })),
        },
      },
    };
    const rosters = await dynamodb.batchGet(batch).promise();
    const rosterMap = new Map(
      (rosters.Responses[ROSTERS_TABLE] || []).map((r) => [r.rosterId, r])
    );

    const result = memberships.Items.map((member) => {
      const roster = rosterMap.get(member.rosterId);
      return {
        roster_id: member.rosterId,
        role: member.role,
          rosters: roster
          ? {
              id: roster.rosterId,
              name: roster.name,
              owner_id: roster.ownerId,
              org_id: roster.orgId ?? null,
              created_at: roster.createdAt,
              updated_at: roster.updatedAt,
              password_protected: Boolean(roster.passwordHash),
            }
          : null,
      };
    });
    return jsonResponse(200, result);
  }

  if (method === "POST" && path === "/rosters/delete") {
    const { rosterId } = parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const canDelete = await ensureRosterRole(rosterId, userId, "owner");
    if (!canDelete) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const roster = await dynamodb
      .get({ TableName: ROSTERS_TABLE, Key: { rosterId } })
      .promise();
    if (!roster.Item) {
      return jsonResponse(404, { error: "Roster not found" });
    }

    const deleteByRosterId = async (tableName, rangeKey) => {
      if (!tableName) return;
      let lastKey = undefined;
      do {
        const query = await dynamodb
          .query({
            TableName: tableName,
            KeyConditionExpression: "rosterId = :rosterId",
            ExpressionAttributeValues: { ":rosterId": rosterId },
            ExclusiveStartKey: lastKey,
          })
          .promise();
        const items = query.Items || [];
        const keys = items
          .map((item) => {
            const key = { rosterId };
            if (rangeKey) key[rangeKey] = item[rangeKey];
            return key;
          })
          .filter(
            (key) => !rangeKey || key[rangeKey] !== undefined && key[rangeKey] !== null
          );
        if (keys.length) {
          await batchDelete(tableName, keys);
        }
        lastKey = query.LastEvaluatedKey;
      } while (lastKey);
    };

    const deleteShareCodes = async () => {
      const items = [];
      let lastKey = undefined;
      do {
        const scan = await dynamodb
          .scan({
            TableName: SHARE_CODES_TABLE,
            FilterExpression: "rosterId = :rosterId",
            ExpressionAttributeValues: { ":rosterId": rosterId },
            ExclusiveStartKey: lastKey,
          })
          .promise();
        items.push(...(scan.Items || []));
        lastKey = scan.LastEvaluatedKey;
      } while (lastKey);
      if (!items.length) return;
      await batchDelete(
        SHARE_CODES_TABLE,
        items.map((item) => ({ code: item.code }))
      );
    };

    await deleteByRosterId(ROSTER_MEMBERS_TABLE, "userId");
    await deleteByRosterId(ROSTER_DATA_TABLE, null);
    await deleteByRosterId(ROSTER_UPDATES_TABLE, "updateId");
    await deleteByRosterId(AVAILABILITY_REQUESTS_TABLE, "requestId");
    await deleteByRosterId(SWAP_REQUESTS_TABLE, "requestId");
    await deleteByRosterId(SHIFT_LOCKS_TABLE, "lockId");
    await deleteByRosterId(CHANGE_PROPOSALS_TABLE, "proposalId");
    await deleteByRosterId(AUDIT_LOGS_TABLE, "logId");
    await deleteByRosterId(PRESENCE_TABLE, "userId");
    await deleteByRosterId(TIME_CLOCK_TABLE, "entryId");
    await deleteByRosterId(AI_FEEDBACK_TABLE, "feedbackId");
    await deleteByRosterId(ANALYTICS_TABLE, "eventId");
    await deleteShareCodes();

    await dynamodb
      .delete({
        TableName: ROSTERS_TABLE,
        Key: { rosterId },
      })
      .promise();

    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_deleted",
      metadata: { name: roster.Item.name },
    });

    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/rosters/rename") {
    const { rosterId, name } = parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    if (!name) return jsonResponse(400, { error: "Missing roster name" });
    const canRename = await ensureRosterRole(rosterId, userId, "owner");
    if (!canRename) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: ROSTERS_TABLE,
        Key: { rosterId },
        UpdateExpression: "SET #name = :name, updatedAt = :updatedAt",
        ExpressionAttributeNames: { "#name": "name" },
        ExpressionAttributeValues: {
          ":name": name,
          ":updatedAt": now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_renamed",
      metadata: { name },
      timestamp: now,
    });
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/roster/save") {
    const { rosterId, data, reason } = parseBody(event);
    if (!rosterId || !data) {
      return jsonResponse(400, { error: "Missing rosterId or data" });
    }
    const canEdit = await ensureRosterRole(rosterId, userId, "member");
    if (!canEdit) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const now = new Date().toISOString();
    const current = await dynamodb
      .get({ TableName: ROSTER_DATA_TABLE, Key: { rosterId } })
      .promise();
    const prevData = current.Item?.data;
    const prevVersion = current.Item?.version ?? 0;
    const patchSummary = diffJson(prevData, data, []);
    const patch = patchSummary.ops || [];
    const changedSections = Array.from(patchSummary.summary || []);

    const update = await dynamodb
      .update({
        TableName: ROSTER_DATA_TABLE,
        Key: { rosterId },
        UpdateExpression:
          "SET #data = :data, #version = if_not_exists(#version, :zero) + :inc, #last = :last, #by = :by",
        ExpressionAttributeNames: {
          "#data": "data",
          "#version": "version",
          "#last": "lastModified",
          "#by": "lastModifiedBy",
        },
        ExpressionAttributeValues: {
          ":data": data,
          ":zero": 0,
          ":inc": 1,
          ":last": now,
          ":by": userId,
        },
        ReturnValues: "ALL_NEW",
      })
      .promise();

    const newVersion = update.Attributes.version;
    const storeSnapshot =
      !prevData ||
      newVersion % ROSTER_VERSION_SNAPSHOT_INTERVAL === 0 ||
      patch.length > ROSTER_VERSION_MAX_OPS;
    await writeRosterVersionEntry({
      rosterId,
      version: newVersion,
      baseVersion: storeSnapshot ? newVersion : prevVersion,
      fromVersion: prevVersion,
      userId,
      reason,
      patch,
      changedSections,
      snapshot: storeSnapshot ? data : null,
      timestamp: now,
    });

    const updateId = `${Date.now()}_${userId}`;
    await dynamodb
      .put({
        TableName: ROSTER_UPDATES_TABLE,
        Item: {
          rosterId,
          updateId,
          roster_id: rosterId,
          user_id: userId,
          operation_type: 0,
          data: { version: update.Attributes.version, last_modified_by: userId },
          timestamp: now,
        },
      })
      .promise();

    const accessCode =
      event.headers?.["x-share-code"] || event.headers?.["X-Share-Code"];
    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_saved",
      metadata: {
        version: update.Attributes.version,
        accessCode: accessCode || null,
        source: accessCode ? "access_code" : "owner",
        changedSections,
      },
      timestamp: now,
    });

    return jsonResponse(200, {
      version: update.Attributes.version,
      last_modified: update.Attributes.lastModified,
      last_modified_by: update.Attributes.lastModifiedBy,
    });
  }

  if (method === "GET" && path === "/roster/load") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const data = await dynamodb
      .get({ TableName: ROSTER_DATA_TABLE, Key: { rosterId } })
      .promise();
    if (!data.Item) return jsonResponse(200, null);
    return jsonResponse(200, {
      data: data.Item.data,
      version: data.Item.version ?? 0,
      last_modified: data.Item.lastModified ?? null,
      last_modified_by: data.Item.lastModifiedBy ?? null,
    });
  }

  if (method === "POST" && path === "/roster/update") {
    const { rosterId, update } = parseBody(event);
    if (!rosterId || !update) {
      return jsonResponse(400, { error: "Missing rosterId or update" });
    }
    const canEdit = await ensureRosterRole(rosterId, userId, "member");
    if (!canEdit) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const now = new Date().toISOString();
    const updateId = update.id || `${Date.now()}_${userId}`;
    await dynamodb
      .put({
        TableName: ROSTER_UPDATES_TABLE,
        Item: {
          rosterId,
          updateId,
          roster_id: update.roster_id ?? rosterId,
          user_id: update.user_id ?? userId,
          operation_type: update.operation_type ?? 0,
          data: update.data ?? {},
          timestamp: update.timestamp ?? now,
        },
      })
      .promise();
    const accessCode =
      event.headers?.["x-share-code"] || event.headers?.["X-Share-Code"];
    const updateMeta = {
      updateId,
      operationType: update.operation_type ?? 0,
      dataKeys: Object.keys(update.data || {}),
    };
    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_update",
      metadata: accessCode
        ? { ...updateMeta, accessCode, source: "access_code" }
        : { ...updateMeta, source: "owner" },
      timestamp: now,
    });
    return jsonResponse(200, { ok: true });
  }

  if (method === "GET" && path === "/roster/updates") {
    const rosterId = event.queryStringParameters?.rosterId;
    const since = event.queryStringParameters?.since;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const query = await dynamodb
      .query({
        TableName: ROSTER_UPDATES_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: {
          ":rosterId": rosterId,
        },
        Limit: 50,
        ScanIndexForward: true,
      })
      .promise();
    const items = query.Items || [];
    const filtered = since
      ? items.filter((item) => item.timestamp > since)
      : items;
    return jsonResponse(200, filtered);
  }

  if (method === "GET" && path === "/roster/versions") {
    const rosterId = event.queryStringParameters?.rosterId;
    const limitRaw = event.queryStringParameters?.limit;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    if (!ROSTER_VERSIONS_TABLE) {
      return jsonResponse(200, []);
    }
    const limit = Math.min(
      Math.max(parseInt(limitRaw || "25", 10) || 25, 1),
      200
    );
    const query = await dynamodb
      .query({
        TableName: ROSTER_VERSIONS_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: {
          ":rosterId": rosterId,
        },
        ScanIndexForward: false,
        Limit: limit,
      })
      .promise();
    const items = (query.Items || []).map((item) => ({
      rosterId: item.rosterId,
      version: item.version,
      fromVersion: item.fromVersion ?? null,
      baseVersion: item.baseVersion ?? null,
      userId: item.userId ?? null,
      reason: item.reason ?? "",
      diffCount: item.diffCount ?? 0,
      changedSections: item.changedSections ?? [],
      hasSnapshot: Boolean(item.snapshot),
      timestamp: item.timestamp ?? null,
    }));
    return jsonResponse(200, items);
  }

  if (method === "POST" && path === "/roster/rollback") {
    const { rosterId, targetVersion, reason } = parseBody(event);
    if (!rosterId || targetVersion == null) {
      return jsonResponse(400, { error: "Missing rosterId or targetVersion" });
    }
    const canEdit = await ensureRosterRole(rosterId, userId, "owner");
    if (!canEdit) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    if (!ROSTER_VERSIONS_TABLE) {
      return jsonResponse(500, { error: "Versioning not configured" });
    }

    const target = Number(targetVersion);
    if (Number.isNaN(target) || target < 1) {
      return jsonResponse(400, { error: "Invalid targetVersion" });
    }

    const current = await dynamodb
      .get({ TableName: ROSTER_DATA_TABLE, Key: { rosterId } })
      .promise();
    if (!current.Item) {
      return jsonResponse(404, { error: "Roster not found" });
    }
    const currentData = current.Item.data;
    const currentVersion = current.Item.version ?? 0;

    let snapshotVersion = null;
    let snapshotData = null;
    let lastKey = undefined;
    do {
      const page = await dynamodb
        .query({
          TableName: ROSTER_VERSIONS_TABLE,
          KeyConditionExpression: "rosterId = :rosterId AND #version <= :v",
          ExpressionAttributeNames: { "#version": "version" },
          ExpressionAttributeValues: {
            ":rosterId": rosterId,
            ":v": target,
          },
          ScanIndexForward: false,
          ExclusiveStartKey: lastKey,
        })
        .promise();
      const items = page.Items || [];
      for (const item of items) {
        if (item.snapshot) {
          snapshotVersion = item.version;
          snapshotData = item.snapshot;
          break;
        }
      }
      if (snapshotData) break;
      lastKey = page.LastEvaluatedKey;
    } while (lastKey);

    if (snapshotData == null) {
      return jsonResponse(404, { error: "No snapshot found to rollback" });
    }

    let data = deepClone(snapshotData);
    if (snapshotVersion < target) {
      let patchKey = undefined;
      const patches = [];
      do {
        const page = await dynamodb
          .query({
            TableName: ROSTER_VERSIONS_TABLE,
            KeyConditionExpression:
              "rosterId = :rosterId AND #version BETWEEN :from AND :to",
            ExpressionAttributeNames: { "#version": "version" },
            ExpressionAttributeValues: {
              ":rosterId": rosterId,
              ":from": snapshotVersion + 1,
              ":to": target,
            },
            ScanIndexForward: true,
            ExclusiveStartKey: patchKey,
          })
          .promise();
        patches.push(...(page.Items || []));
        patchKey = page.LastEvaluatedKey;
      } while (patchKey);

      for (const entry of patches) {
        if (entry.diff && Array.isArray(entry.diff)) {
          data = applyPatch(data, entry.diff);
        }
      }
    }

    const now = new Date().toISOString();
    const patchSummary = diffJson(currentData, data, []);
    const patch = patchSummary.ops || [];
    const changedSections = Array.from(patchSummary.summary || []);

    const update = await dynamodb
      .update({
        TableName: ROSTER_DATA_TABLE,
        Key: { rosterId },
        UpdateExpression:
          "SET #data = :data, #version = if_not_exists(#version, :zero) + :inc, #last = :last, #by = :by",
        ExpressionAttributeNames: {
          "#data": "data",
          "#version": "version",
          "#last": "lastModified",
          "#by": "lastModifiedBy",
        },
        ExpressionAttributeValues: {
          ":data": data,
          ":zero": 0,
          ":inc": 1,
          ":last": now,
          ":by": userId,
        },
        ReturnValues: "ALL_NEW",
      })
      .promise();

    const newVersion = update.Attributes.version;
    await writeRosterVersionEntry({
      rosterId,
      version: newVersion,
      baseVersion: newVersion,
      fromVersion: currentVersion,
      userId,
      reason: reason || `Rollback to v${target}`,
      patch,
      changedSections,
      snapshot: data,
      timestamp: now,
    });

    const updateId = `${Date.now()}_${userId}`;
    await dynamodb
      .put({
        TableName: ROSTER_UPDATES_TABLE,
        Item: {
          rosterId,
          updateId,
          roster_id: rosterId,
          user_id: userId,
          operation_type: 3,
          data: { rollbackTo: target, newVersion },
          timestamp: now,
        },
      })
      .promise();

    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_rollback",
      metadata: { targetVersion: target, newVersion },
      timestamp: now,
    });

    return jsonResponse(200, {
      ok: true,
      targetVersion: target,
      version: newVersion,
      last_modified: update.Attributes.lastModified,
      last_modified_by: update.Attributes.lastModifiedBy,
    });
  }

  if (method === "POST" && path === "/profile") {
    const { displayName, email } = parseBody(event);
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET #displayName = :displayName, #email = :email, #updatedAt = :updatedAt",
        ExpressionAttributeNames: {
          "#displayName": "displayName",
          "#email": "email",
          "#updatedAt": "updatedAt",
        },
        ExpressionAttributeValues: {
          ":displayName": displayName ?? "User",
          ":email": email ?? "",
          ":updatedAt": now,
        },
      })
      .promise();
    return jsonResponse(200, { ok: true });
  }

  if (method === "GET" && path === "/profile/get") {
    const config = await getRuntimeConfig();
    const profile = await dynamodb
      .get({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
      })
      .promise();
    let item = profile.Item || {};
    const now = new Date();

    if (!item.trialStartAt && !item.subscriptionStatus) {
      const emailLower = (item.email || "").toString().toLowerCase().trim();
      const history = await getTrialHistoryRecord(emailLower);
      if (history) {
        await dynamodb
          .update({
            TableName: USER_PROFILES_TABLE,
            Key: { userId },
            UpdateExpression:
              "SET subscriptionStatus = :status, subscriptionPlan = :plan, updatedAt = :updatedAt",
            ExpressionAttributeValues: {
              ":status": "inactive",
              ":plan": "none",
              ":updatedAt": now.toISOString(),
            },
          })
          .promise();
        item = {
          ...item,
          subscriptionStatus: "inactive",
          subscriptionPlan: "none",
        };
      } else {
        const trialStartAt = now.toISOString();
        const trialExpiresAt = new Date(
          now.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000
        ).toISOString();
        await dynamodb
          .update({
            TableName: USER_PROFILES_TABLE,
            Key: { userId },
            UpdateExpression:
              "SET trialStartAt = :trialStartAt, trialExpiresAt = :trialExpiresAt, subscriptionStatus = :status, subscriptionPlan = if_not_exists(subscriptionPlan, :plan), updatedAt = :updatedAt",
            ExpressionAttributeValues: {
              ":trialStartAt": trialStartAt,
              ":trialExpiresAt": trialExpiresAt,
              ":status": "trialing",
              ":plan": "trial",
              ":updatedAt": now.toISOString(),
            },
          })
          .promise();
        item = {
          ...item,
          trialStartAt,
          trialExpiresAt,
          subscriptionStatus: "trialing",
          subscriptionPlan: item.subscriptionPlan || "trial",
        };
        if (emailLower) {
          await recordTrialHistory({
            emailLower,
            email: item.email || "",
            userId,
            source: "profile_get",
          });
        }
      }
    }

    const trial = getTrialState(item);
    if (
      item.subscriptionStatus?.toLowerCase() === "trialing" &&
      !trial.active
    ) {
      await dynamodb
        .update({
          TableName: USER_PROFILES_TABLE,
          Key: { userId },
          UpdateExpression:
            "SET subscriptionStatus = :status, updatedAt = :updatedAt",
          ExpressionAttributeValues: {
            ":status": "inactive",
            ":updatedAt": now.toISOString(),
          },
        })
        .promise();
      item = {
        ...item,
        subscriptionStatus: "inactive",
      };
    }

    const planValue = (item.subscriptionPlan || "").toString().toLowerCase();
    const statusValue = (item.subscriptionStatus || "").toString().toLowerCase();
    const lastPlanRefreshAt = item.subscriptionPlanCheckedAt
      ? Date.parse(item.subscriptionPlanCheckedAt)
      : 0;
    const planStale =
      !lastPlanRefreshAt ||
      Number.isNaN(lastPlanRefreshAt) ||
      now.getTime() - lastPlanRefreshAt > 6 * 60 * 60 * 1000;
    const needsPlanRefresh =
      (statusValue === "active" || statusValue === "trialing") &&
      (planValue === "" ||
        planValue === "none" ||
        planValue === "trial");
    if (needsPlanRefresh && planStale && config.stripe.secretKey) {
      try {
        const resolved = await resolveStripeSubscription({
          config,
          customerId: item.stripeCustomerId,
          email: item.email || getUserEmail(event) || "",
          subscriptionId: item.stripeSubscriptionId,
        });
        if (resolved && resolved.subscriptionId) {
          await updateSubscriptionRecord({
            userId,
            customerId: resolved.customerId,
            status: resolved.status,
            plan: resolved.plan,
            subscriptionId: resolved.subscriptionId,
            currentPeriodEnd: resolved.currentPeriodEnd,
            config,
          });
          await dynamodb
            .update({
              TableName: USER_PROFILES_TABLE,
              Key: { userId },
              UpdateExpression:
                "SET subscriptionPlanCheckedAt = :checkedAt",
              ExpressionAttributeValues: {
                ":checkedAt": now.toISOString(),
              },
            })
            .promise();
          item = {
            ...item,
            subscriptionStatus: resolved.status,
            subscriptionPlan: normalizePlan(resolved.plan, config),
            stripeCustomerId: resolved.customerId || item.stripeCustomerId,
            stripeSubscriptionId:
              resolved.subscriptionId || item.stripeSubscriptionId,
            subscriptionPeriodEnd:
              resolved.currentPeriodEnd || item.subscriptionPeriodEnd,
            subscriptionPlanCheckedAt: now.toISOString(),
          };
        } else {
          await dynamodb
            .update({
              TableName: USER_PROFILES_TABLE,
              Key: { userId },
              UpdateExpression:
                "SET subscriptionPlanCheckedAt = :checkedAt",
              ExpressionAttributeValues: {
                ":checkedAt": now.toISOString(),
              },
            })
            .promise();
        }
      } catch (error) {
        console.warn("Profile plan refresh failed", error);
      }
    }

    const usageSnapshot = buildUsageSnapshot(item, config);
    return jsonResponse(200, {
      ...item,
      trialActive: trial.active,
      trialEndsAt: trial.expiresAt || item.trialExpiresAt || null,
      usageSnapshot,
    });
  }

  if (method === "POST" && path === "/billing/checkout") {
    const { plan } = parseBody(event);
    const config = await getRuntimeConfig({ forceSecretsReload: true });
    const normalizedPlan = String(plan ?? "").trim().toLowerCase();
    const priceId =
      config.stripe.prices?.[normalizedPlan] ??
      config.stripe.prices?.[plan];
    if (!priceId) {
      return jsonResponse(400, {
        error: "Invalid plan",
        plan: normalizedPlan || plan || null,
      });
    }
    if (!config.stripe.secretKey) {
      return jsonResponse(500, { error: "Stripe not configured" });
    }
    const email = getUserEmail(event);
    const profile = await dynamodb
      .get({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
      })
      .promise();
    let customerId = profile.Item?.stripeCustomerId;
    if (!customerId) {
      try {
        const customer = await stripeRequest({
          path: "/v1/customers",
          secretKey: config.stripe.secretKey,
          body: {
            email: email ?? "",
            "metadata[userId]": userId,
          },
        });
        customerId = customer.id;
        await dynamodb
          .update({
            TableName: USER_PROFILES_TABLE,
            Key: { userId },
            UpdateExpression:
              "SET stripeCustomerId = :customerId, updatedAt = :updatedAt",
            ExpressionAttributeValues: {
              ":customerId": customerId,
              ":updatedAt": new Date().toISOString(),
            },
          })
          .promise();
      } catch (error) {
        console.error("Stripe customer create failed", error);
        return jsonResponse(error.statusCode || 500, {
          error: "Stripe customer create failed",
          message: error.message || "Stripe error",
          details: error.details || null,
        });
      }
    }
    const successUrl =
      config.stripe.successUrl || "https://rosterchampion.com/billing/success";
    const cancelUrl =
      config.stripe.cancelUrl || "https://rosterchampion.com/billing/cancel";
    let session;
    try {
      session = await stripeRequest({
        path: "/v1/checkout/sessions",
        secretKey: config.stripe.secretKey,
        body: {
          mode: "subscription",
          customer: customerId,
          "line_items[0][price]": priceId,
          "line_items[0][quantity]": "1",
          success_url: successUrl,
          cancel_url: cancelUrl,
          "metadata[userId]": userId,
          "subscription_data[metadata][userId]": userId,
          "subscription_data[metadata][plan]": plan,
        },
      });
    } catch (error) {
      console.error("Stripe checkout failed", error);
      return jsonResponse(error.statusCode || 500, {
        error: "Stripe checkout failed",
        message: error.message || "Stripe error",
        details: error.details || null,
      });
    }
    return jsonResponse(200, {
      url: session.url,
      sessionId: session.id,
    });
  }

  if (method === "POST" && path === "/billing/portal") {
    const config = await getRuntimeConfig();
    if (!config.stripe.secretKey) {
      return jsonResponse(500, { error: "Stripe not configured" });
    }
    const profile = await dynamodb
      .get({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
      })
      .promise();
    const customerId = profile.Item?.stripeCustomerId;
    if (!customerId) {
      return jsonResponse(400, { error: "No billing profile found" });
    }
    let portal;
    try {
      portal = await stripeRequest({
        path: "/v1/billing_portal/sessions",
        secretKey: config.stripe.secretKey,
        body: {
          customer: customerId,
          return_url:
            config.stripe.portalReturnUrl ||
            "https://rosterchampion.com/billing",
        },
      });
    } catch (error) {
      console.error("Stripe portal failed", error);
      return jsonResponse(error.statusCode || 500, {
        error: "Stripe portal failed",
        message: error.message || "Stripe error",
        details: error.details || null,
      });
    }
    return jsonResponse(200, { url: portal.url });
  }

  if (method === "POST" && path === "/billing/reconcile") {
    const config = await getRuntimeConfig({ forceSecretsReload: true });
    if (!config.stripe.secretKey) {
      return jsonResponse(500, { error: "Stripe not configured" });
    }
    const body = parseBody(event);
    const admin = isAdminUser(event);
    let targetUserId = userId;
    if (admin && body?.userId) {
      targetUserId = body.userId;
    } else if (admin && body?.email) {
      const normalizedEmail = String(body.email).toLowerCase().trim();
      const found = await findProfileByEmail(normalizedEmail, body.email);
      if (found?.userId) {
        targetUserId = found.userId;
      }
    }
    if (!targetUserId) {
      return jsonResponse(400, { error: "Missing userId" });
    }
    const profile = await getUserProfile(targetUserId);
    if (!profile) {
      return jsonResponse(404, { error: "User not found" });
    }
    try {
      await updateBillingSystemRecord({
        lastReconcileAt: new Date().toISOString(),
        lastReconcileSource: admin ? "admin" : "user",
        lastReconcileStatus: "running",
      });
      const resolved = await resolveStripeSubscription({
        config,
        customerId: profile.stripeCustomerId,
        email: profile.email || body?.email || getUserEmail(event) || "",
        subscriptionId: profile.stripeSubscriptionId,
      });
      if (!resolved || !resolved.subscriptionId) {
        await updateBillingSystemRecord({
          lastReconcileStatus: "no_subscription",
          lastReconcileUserId: targetUserId,
        });
        await writeBillingAudit({
          userId: targetUserId,
          action: "reconcile_user_no_subscription",
          status: "inactive",
          plan: profile.subscriptionPlan || null,
          source: admin ? "admin" : "user",
          detail: "No active Stripe subscription found",
        });
        return jsonResponse(200, {
          ok: true,
          updated: false,
          reason: "no_subscription",
          customerId: resolved?.customerId || profile.stripeCustomerId || null,
        });
      }
      await updateSubscriptionRecord({
        userId: targetUserId,
        customerId: resolved.customerId,
        status: resolved.status,
        plan: resolved.plan,
        subscriptionId: resolved.subscriptionId,
        currentPeriodEnd: resolved.currentPeriodEnd,
        config,
      });
      await enforceShareCodeLimitsForUser({
        userId: targetUserId,
        status: resolved.status,
        plan: resolved.plan,
        config,
      });
      await updateBillingSystemRecord({
        lastReconcileStatus: "ok",
        lastReconcileUserId: targetUserId,
      });
      await writeBillingAudit({
        userId: targetUserId,
        action: "reconcile_user",
        status: resolved.status,
        plan: normalizePlan(resolved.plan, config),
        source: admin ? "admin" : "user",
        detail: "Subscription synchronized",
      });
      return jsonResponse(200, {
        ok: true,
        updated: true,
        status: resolved.status,
        plan: normalizePlan(resolved.plan, config),
        subscriptionPeriodEnd: resolved.currentPeriodEnd || null,
      });
    } catch (error) {
      console.error("Billing reconcile failed", error);
      await updateBillingSystemRecord({
        lastReconcileStatus: "error",
        lastReconcileUserId: targetUserId,
        lastReconcileError: error.message || "Stripe error",
      });
      await writeBillingAudit({
        userId: targetUserId,
        action: "reconcile_user_error",
        status: "error",
        plan: profile.subscriptionPlan || null,
        source: admin ? "admin" : "user",
        detail: error.message || "Stripe error",
      });
      return jsonResponse(error.statusCode || 500, {
        error: "Billing reconcile failed",
        message: error.message || "Stripe error",
        details: error.details || null,
      });
    }
  }

  if (method === "POST" && path === "/billing/reconcile-all") {
    const config = await getRuntimeConfig({ forceSecretsReload: true });
    if (!config.stripe.secretKey) {
      return jsonResponse(500, { error: "Stripe not configured" });
    }
    if (!isAdminUser(event)) {
      return jsonResponse(403, { error: "Admin only" });
    }
    await updateBillingSystemRecord({
      lastReconcileAt: new Date().toISOString(),
      lastReconcileSource: "admin-bulk",
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
            "userId, email, stripeCustomerId, stripeSubscriptionId, subscriptionStatus, subscriptionPlan",
          ExclusiveStartKey: lastKey,
        })
        .promise();
      const items = response.Items || [];
      for (const item of items) {
        if (!item.userId || item.userId === BILLING_SYSTEM_ID) continue;
        results.scanned += 1;
        const customerId = item.stripeCustomerId;
        const email = item.email || "";
        if (!customerId && !email) {
          results.skipped += 1;
          continue;
        }
        try {
          const resolved = await resolveStripeSubscription({
            config,
            customerId,
            email,
            subscriptionId: item.stripeSubscriptionId,
          });
          if (!resolved || !resolved.subscriptionId) {
            results.skipped += 1;
            continue;
          }
          await updateSubscriptionRecord({
            userId: item.userId,
            customerId: resolved.customerId,
            status: resolved.status,
            plan: resolved.plan,
            subscriptionId: resolved.subscriptionId,
            currentPeriodEnd: resolved.currentPeriodEnd,
            config,
          });
          await enforceShareCodeLimitsForUser({
            userId: item.userId,
            status: resolved.status,
            plan: resolved.plan,
            config,
          });
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
    await writeBillingAudit({
      userId: "system",
      action: "reconcile_all",
      status: "ok",
      plan: null,
      source: "admin-bulk",
      detail: JSON.stringify(results),
    });
    return jsonResponse(200, {
      ok: true,
      results,
      truncated: Date.now() - startedAt > 20000,
    });
  }

  if (method === "POST" && path === "/billing/webhook") {
    const config = await getRuntimeConfig();
    const signature = stripeSignatureHeader(event);
    const rawBody = getRawBody(event);
    if (!config.stripe.webhookSecret) {
      console.warn("Stripe webhook secret not configured; skipping signature verification.");
    } else {
      const isValid = verifyStripeSignature(
        rawBody,
        signature,
        config.stripe.webhookSecret
      );
      if (!isValid) {
        return jsonResponse(400, { error: "Invalid signature" });
      }
    }
    let stripeEvent;
    try {
      stripeEvent = JSON.parse(rawBody.toString("utf8"));
    } catch {
      return jsonResponse(400, { error: "Invalid payload" });
    }

    await updateBillingSystemRecord({
      lastWebhookAt: new Date().toISOString(),
      lastWebhookType: stripeEvent.type || "unknown",
      lastWebhookEventId: stripeEvent.id || null,
    });

    if (BILLING_EVENTS_BUS) {
      try {
        await new AWS.EventBridge()
          .putEvents({
            Entries: [
              {
                EventBusName: BILLING_EVENTS_BUS,
                Source: "stripe",
                DetailType: stripeEvent.type || "stripe.event",
                Detail: JSON.stringify(stripeEvent),
              },
            ],
          })
          .promise();
      } catch (err) {
        console.warn("Failed to publish billing event", err);
      }
    }

    const type = stripeEvent.type;
    const data = stripeEvent.data?.object || {};
    if (type === "checkout.session.completed") {
      const userIdFromMeta =
        data.metadata?.userId || data.client_reference_id || null;
      let subscriptionDetails = null;
      if (data.subscription && config.stripe.secretKey) {
        try {
          subscriptionDetails = await stripeGet({
            path: `/v1/subscriptions/${data.subscription}`,
            secretKey: config.stripe.secretKey,
          });
        } catch (error) {
          console.warn("Stripe subscription fetch failed", error);
        }
      }
      await updateSubscriptionRecord({
        userId: userIdFromMeta,
        customerId: data.customer,
        status: subscriptionDetails?.status || "active",
        plan:
          subscriptionDetails?.metadata?.plan ||
          subscriptionDetails?.items?.data?.[0]?.price?.id ||
          data.metadata?.plan ||
          "",
        subscriptionId: data.subscription,
        currentPeriodEnd: subscriptionDetails?.current_period_end
          ? new Date(subscriptionDetails.current_period_end * 1000).toISOString()
          : null,
        config,
      });
      await enforceShareCodeLimitsForUser({
        userId: userIdFromMeta,
        status: subscriptionDetails?.status || "active",
        plan:
          subscriptionDetails?.metadata?.plan ||
          subscriptionDetails?.items?.data?.[0]?.price?.id ||
          data.metadata?.plan ||
          "",
        config,
      });
      await writeBillingAudit({
        userId: userIdFromMeta,
        action: "checkout_completed",
        status: subscriptionDetails?.status || "active",
        plan: normalizePlan(
          subscriptionDetails?.metadata?.plan ||
            subscriptionDetails?.items?.data?.[0]?.price?.id ||
            data.metadata?.plan ||
            "",
          config
        ),
        source: "stripe",
        detail: `checkout_session:${data.id || ""}`,
      });
    }

    if (
      type === "customer.subscription.created" ||
      type === "customer.subscription.updated" ||
      type === "customer.subscription.deleted"
    ) {
      const subscription = data;
      const userIdFromMeta = subscription.metadata?.userId || null;
      const customerId = subscription.customer;
      const resolvedUserId =
        userIdFromMeta || (await findUserIdByCustomer(customerId));
      await updateSubscriptionRecord({
        userId: resolvedUserId,
        customerId,
        status: subscription.status,
        plan:
          subscription.metadata?.plan ||
          subscription.items?.data?.[0]?.price?.id ||
          "",
        subscriptionId: subscription.id,
        currentPeriodEnd: subscription.current_period_end
          ? new Date(subscription.current_period_end * 1000).toISOString()
          : null,
        config,
      });
      await enforceShareCodeLimitsForUser({
        userId: resolvedUserId,
        status: subscription.status,
        plan:
          subscription.metadata?.plan ||
          subscription.items?.data?.[0]?.price?.id ||
          "",
        config,
      });
      await writeBillingAudit({
        userId: resolvedUserId,
        action: type,
        status: subscription.status,
        plan: normalizePlan(
          subscription.metadata?.plan ||
            subscription.items?.data?.[0]?.price?.id ||
            "",
          config
        ),
        source: "stripe",
        detail: `subscription:${subscription.id || ""}`,
      });
    }

    if (type === "invoice.payment_succeeded") {
      const invoice = data;
      const customerId = invoice.customer;
      const resolvedUserId = await findUserIdByCustomer(customerId);
      await updateSubscriptionRecord({
        userId: resolvedUserId,
        customerId,
        status: "active",
        plan:
          invoice.lines?.data?.[0]?.price?.id ||
          invoice.metadata?.plan ||
          "",
        subscriptionId: invoice.subscription,
        currentPeriodEnd: invoice.lines?.data?.[0]?.period?.end
          ? new Date(invoice.lines.data[0].period.end * 1000).toISOString()
          : null,
        config,
      });
      await enforceShareCodeLimitsForUser({
        userId: resolvedUserId,
        status: "active",
        plan:
          invoice.lines?.data?.[0]?.price?.id ||
          invoice.metadata?.plan ||
          "",
        config,
      });
      await writeBillingAudit({
        userId: resolvedUserId,
        action: "invoice_payment_succeeded",
        status: "active",
        plan: normalizePlan(
          invoice.lines?.data?.[0]?.price?.id || invoice.metadata?.plan || "",
          config
        ),
        source: "stripe",
        detail: `invoice:${invoice.id || ""}`,
      });
    }

    return jsonResponse(200, { received: true });
  }

  if (method === "GET" && path === "/settings/get") {
    const profile = await dynamodb
      .get({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
      })
      .promise();
    return jsonResponse(200, profile.Item?.settings || {});
  }

  if (method === "POST" && path === "/settings/save") {
    const { settings } = parseBody(event);
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET #settings = :settings, #updatedAt = :updatedAt",
        ExpressionAttributeNames: {
          "#settings": "settings",
          "#updatedAt": "updatedAt",
        },
        ExpressionAttributeValues: {
          ":settings": settings ?? {},
          ":updatedAt": now,
        },
      })
      .promise();
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/contact") {
    const { name, email, message, source } = parseBody(event);
    if (!name || !email || !message) {
      return jsonResponse(400, { error: "Missing name, email, or message" });
    }
    if (message.length > 4000) {
      return jsonResponse(400, { error: "Message too long" });
    }
    const subject = `Roster Champion Contact (${source || "website"})`;
    const body = `Name: ${name}\nEmail: ${email}\nSource: ${source || "unknown"}\n\nMessage:\n${message}`;
    try {
      await sendEmail({
        to: "support@rosterchampion.com",
        subject,
        body,
        replyTo: email,
      });
      return jsonResponse(200, { ok: true });
    } catch (error) {
      console.error("Contact email failed", error);
      return jsonResponse(500, {
        error: "Email send failed",
        message: error.message || "Unable to send message",
      });
    }
  }

  if (method === "POST" && path === "/billing/payment-sheet") {
    const { plan } = parseBody(event);
    const config = await getRuntimeConfig({ forceSecretsReload: true });
    const normalizedPlan = String(plan ?? "").trim().toLowerCase();
    const priceId =
      config.stripe.prices?.[normalizedPlan] ??
      config.stripe.prices?.[plan];
    if (!priceId) {
      return jsonResponse(400, {
        error: "Invalid plan",
        plan: normalizedPlan || plan || null,
      });
    }
    if (!config.stripe.secretKey) {
      return jsonResponse(500, { error: "Stripe not configured" });
    }
    if (!config.stripe.publishableKey) {
      return jsonResponse(500, { error: "Stripe publishable key missing" });
    }
    const email = getUserEmail(event);
    const profile = await dynamodb
      .get({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
      })
      .promise();
    let customerId = profile.Item?.stripeCustomerId;
    if (!customerId) {
      const customer = await stripeRequest({
        path: "/v1/customers",
        secretKey: config.stripe.secretKey,
        body: {
          email: email ?? "",
          "metadata[userId]": userId,
        },
      });
      customerId = customer.id;
      await dynamodb
        .update({
          TableName: USER_PROFILES_TABLE,
          Key: { userId },
          UpdateExpression:
            "SET stripeCustomerId = :customerId, updatedAt = :updatedAt",
          ExpressionAttributeValues: {
            ":customerId": customerId,
            ":updatedAt": new Date().toISOString(),
          },
        })
        .promise();
    }

    const subscription = await stripeRequest({
      path: "/v1/subscriptions",
      secretKey: config.stripe.secretKey,
      body: {
        customer: customerId,
        "items[0][price]": priceId,
        payment_behavior: "default_incomplete",
        "expand[0]": "latest_invoice.payment_intent",
      },
    });
    const paymentIntent =
      subscription.latest_invoice?.payment_intent?.client_secret || null;
    if (!paymentIntent) {
      return jsonResponse(500, { error: "Stripe payment intent missing" });
    }

    const ephemeralKey = await stripeRequest({
      path: "/v1/ephemeral_keys",
      secretKey: config.stripe.secretKey,
      stripeVersion: "2023-10-16",
      body: { customer: customerId },
    });

    return jsonResponse(200, {
      customerId,
      ephemeralKey: ephemeralKey.secret,
      paymentIntent,
      publishableKey: config.stripe.publishableKey,
    });
  }

  if (method === "POST" && path === "/exports/roster") {
    const hasAccess = await ensurePlanAccess(userId, "starter");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Starter to export rosters.",
      });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId,
      key: "exports",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Roster export limit reached for this billing period. Upgrade to increase limits.",
        quota,
      });
    }
    const { rosterId } = parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const canExport = await ensureRosterAccess(rosterId, userId);
    if (!canExport) return jsonResponse(403, { error: "Forbidden" });
    if (!EXPORTS_BUCKET) {
      return jsonResponse(500, { error: "Exports bucket not configured" });
    }

    const roster = await dynamodb
      .get({ TableName: ROSTERS_TABLE, Key: { rosterId } })
      .promise();
    const data = await dynamodb
      .get({ TableName: ROSTER_DATA_TABLE, Key: { rosterId } })
      .promise();
    if (!data.Item) return jsonResponse(404, { error: "Roster data missing" });

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const key = `exports/${rosterId}/${userId}/roster_${timestamp}.json`;
    const payload = {
      roster: roster.Item ?? null,
      data: data.Item.data ?? null,
      version: data.Item.version ?? 0,
      exportedAt: new Date().toISOString(),
    };

    await s3
      .putObject({
        Bucket: EXPORTS_BUCKET,
        Key: key,
        Body: JSON.stringify(payload, null, 2),
        ContentType: "application/json",
      })
      .promise();

    const signedUrl = s3.getSignedUrl("getObject", {
      Bucket: EXPORTS_BUCKET,
      Key: key,
      Expires: 3600,
    });

    const cdnUrl = CLOUDFRONT_URL
      ? `https://${CLOUDFRONT_URL}/${key}`
      : null;

    return jsonResponse(200, { key, signedUrl, cdnUrl });
  }

  if (method === "POST" && path === "/account/delete") {
    const userEmail = getUserEmail(event);

    const rosterMemberships = await dynamodb
      .query({
        TableName: ROSTER_MEMBERS_TABLE,
        IndexName: "userId-index",
        KeyConditionExpression: "userId = :userId",
        ExpressionAttributeValues: { ":userId": userId },
      })
      .promise();

    await batchDelete(
      ROSTER_MEMBERS_TABLE,
      (rosterMemberships.Items || []).map((item) => ({
        rosterId: item.rosterId,
        userId: item.userId,
      }))
    );

    const orgMemberships = await dynamodb
      .query({
        TableName: ORG_MEMBERS_TABLE,
        IndexName: "userId-index",
        KeyConditionExpression: "userId = :userId",
        ExpressionAttributeValues: { ":userId": userId },
      })
      .promise();

    await batchDelete(
      ORG_MEMBERS_TABLE,
      (orgMemberships.Items || []).map((item) => ({
        orgId: item.orgId,
        userId: item.userId,
      }))
    );

    const teamMemberships = await dynamodb
      .query({
        TableName: TEAM_MEMBERS_TABLE,
        IndexName: "userId-index",
        KeyConditionExpression: "userId = :userId",
        ExpressionAttributeValues: { ":userId": userId },
      })
      .promise();

    await batchDelete(
      TEAM_MEMBERS_TABLE,
      (teamMemberships.Items || []).map((item) => ({
        teamId: item.teamId,
        userId: item.userId,
      }))
    );

    const availability = await deleteByUserIdIndex({
      tableName: AVAILABILITY_REQUESTS_TABLE,
      userId,
    });
    await batchDelete(
      AVAILABILITY_REQUESTS_TABLE,
      availability.map((item) => ({
        rosterId: item.rosterId,
        requestId: item.requestId,
      }))
    );

    const swaps = await deleteByUserIdIndex({
      tableName: SWAP_REQUESTS_TABLE,
      userId,
    });
    await batchDelete(
      SWAP_REQUESTS_TABLE,
      swaps.map((item) => ({
        rosterId: item.rosterId,
        requestId: item.requestId,
      }))
    );

    await dynamodb
      .delete({
        TableName: USER_PROFILES_TABLE,
        Key: { userId },
      })
      .promise();

    if (USER_POOL_ID && userEmail) {
      try {
        await cognito
          .adminDeleteUser({
            UserPoolId: USER_POOL_ID,
            Username: userEmail,
          })
          .promise();
      } catch (error) {
        console.warn("Cognito delete failed", error);
      }
    }

    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/share/create") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const hasAccess = await ensurePlanAccess(userId, "starter");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
          message: "Upgrade to Starter to create share codes.",
        });
      }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId,
      key: "share_create",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Share code creation limit reached for this billing period. Upgrade to increase limits.",
        quota,
      });
    }
    const { rosterId, role, expiresInHours, maxUses, customCode } =
      parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const canShare = await ensureRosterRole(rosterId, userId, "manager");
    if (!canShare) return jsonResponse(403, { error: "Forbidden" });

    const safeRole = role === "editor" ? "editor" : "viewer";
    const now = new Date().toISOString();
    const profile = await ensureUserProfile(userId);
    const normalizedPlan = normalizePlan(profile?.subscriptionPlan || "", config);
    const limits = sharePlanLimits(normalizedPlan);
    if (!limits.maxUses || !limits.maxMonths) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Starter to create share codes.",
      });
    }
    const maxExpiryHours = monthsToHours(limits.maxMonths);
    const requestedExpiryHours =
      typeof expiresInHours === "number" ? expiresInHours : null;
    if (requestedExpiryHours != null && requestedExpiryHours > maxExpiryHours) {
      return jsonResponse(400, {
        error: "Expiry limit exceeded",
        message: `Maximum expiry for your plan is ${limits.maxMonths} months.`,
        limit: { months: limits.maxMonths, hours: maxExpiryHours },
      });
    }
    if (requestedExpiryHours != null && requestedExpiryHours <= 0) {
      return jsonResponse(400, { error: "Expiry must be greater than 0." });
    }
    const enforcedExpiryHours =
      requestedExpiryHours == null ? maxExpiryHours : requestedExpiryHours;
    const expiresAt = new Date(
      Date.now() + enforcedExpiryHours * 3600 * 1000
    ).toISOString();

    const requestedMaxUses =
      typeof maxUses === "number" ? maxUses : null;
    if (requestedMaxUses != null && requestedMaxUses > limits.maxUses) {
      return jsonResponse(400, {
        error: "Max uses limit exceeded",
        message: `Maximum viewers for your plan is ${limits.maxUses}.`,
        limit: { maxUses: limits.maxUses },
      });
    }
    if (requestedMaxUses != null && requestedMaxUses <= 0) {
      return jsonResponse(400, { error: "Max uses must be greater than 0." });
    }
    const enforcedMaxUses =
      requestedMaxUses == null ? limits.maxUses : requestedMaxUses;

    let code = null;
    if (customCode) {
      const normalized = normalizeShareCode(customCode);
      if (!normalized) {
        return jsonResponse(400, {
          error:
            "Invalid share code format. Use 6-12 characters A-Z and 2-9.",
        });
      }
      const existing = await loadShareCode(normalized);
      if (existing) {
        return jsonResponse(409, {
          error: "Share code already in use.",
          suggestions: suggestShareCodes(normalized),
        });
      }
      code = normalized;
    } else {
      for (let i = 0; i < 6; i++) {
        const candidate = generateShareCode(8);
        const existing = await loadShareCode(candidate);
        if (!existing) {
          code = candidate;
          break;
        }
      }
    }

    if (!code) {
      return jsonResponse(500, { error: "Unable to generate share code" });
    }

    try {
      await dynamodb
        .put({
          TableName: SHARE_CODES_TABLE,
          Item: {
            code,
            rosterId,
            role: safeRole,
            createdBy: userId,
            createdAt: now,
            expiresAt,
            maxUses: enforcedMaxUses,
            uses: 0,
            status: "active",
          },
        })
        .promise();
    } catch (error) {
      console.error("Share code create failed", error);
      return jsonResponse(500, { error: "Share code create failed" });
    }

    await writeAuditLog({
      rosterId,
      userId,
      action: "share_code_created",
      metadata: { code, role: safeRole },
      timestamp: now,
    });

    return jsonResponse(200, {
      code,
      rosterId,
      role: safeRole,
      expiresAt,
      maxUses: enforcedMaxUses,
      limit: {
        maxUses: limits.maxUses,
        maxMonths: limits.maxMonths,
      },
    });
  }

  if (method === "POST" && path === "/share/list") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { rosterId } = parseBody(event);
    const items = await listShareCodesForUser({ userId, rosterId });
    const now = new Date();
    const cleaned = items
      .map((item) => ({
        code: item.code,
        rosterId: item.rosterId,
        role: item.role || "viewer",
        createdAt: item.createdAt,
        expiresAt: item.expiresAt ?? null,
        maxUses: item.maxUses ?? null,
        uses: item.uses ?? 0,
        status: item.status || "active",
        revokedAt: item.revokedAt ?? null,
        revokedBy: item.revokedBy ?? null,
        expired:
          item.expiresAt && new Date(item.expiresAt) < now ? true : false,
      }))
      .sort((a, b) => (b.createdAt || "").localeCompare(a.createdAt || ""));
    return jsonResponse(200, { items: cleaned });
  }

  if (method === "POST" && path === "/share/revoke") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { code } = parseBody(event);
    if (!code) return jsonResponse(400, { error: "Missing code" });
    const share = await loadShareCode(code);
    if (!share) return jsonResponse(404, { error: "Share code not found" });
    if (share.status === "revoked") {
      return jsonResponse(200, { ok: true, status: "revoked" });
    }
    if (share.createdBy !== userId) {
      const canManage = await ensureRosterRole(share.rosterId, userId, "manager");
      if (!canManage) return jsonResponse(403, { error: "Forbidden" });
    }
    await dynamodb
      .update({
        TableName: SHARE_CODES_TABLE,
        Key: { code: share.code },
        UpdateExpression: "SET #status = :status, revokedAt = :revokedAt, revokedBy = :revokedBy",
        ExpressionAttributeNames: { "#status": "status" },
        ExpressionAttributeValues: {
          ":status": "revoked",
          ":revokedAt": new Date().toISOString(),
          ":revokedBy": userId,
        },
      })
      .promise();
    return jsonResponse(200, { ok: true, status: "revoked" });
  }

  if (method === "POST" && path === "/share/access") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { code } = parseBody(event);
    if (!code) return jsonResponse(400, { error: "Missing code" });
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId: share.createdBy || userId,
      key: "share_access",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Share access limit reached for this billing period. Ask the roster owner to upgrade.",
        quota,
      });
    }

    const incremented = await incrementShareUses(share);
    if (!incremented) {
      return jsonResponse(410, { error: "Share code exhausted" });
    }

    const roster = await dynamodb
      .get({ TableName: ROSTERS_TABLE, Key: { rosterId: share.rosterId } })
      .promise();
    const data = await dynamodb
      .get({ TableName: ROSTER_DATA_TABLE, Key: { rosterId: share.rosterId } })
      .promise();

    return jsonResponse(200, {
      rosterId: share.rosterId,
      role: share.role || "viewer",
      rosterName: roster.Item?.name ?? null,
      data: data.Item?.data ?? null,
      version: data.Item?.version ?? 0,
      last_modified: data.Item?.lastModified ?? null,
      last_modified_by: data.Item?.lastModifiedBy ?? null,
    });
  }

  if (method === "POST" && path === "/share/validate") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { code } = parseBody(event);
    if (!code) return jsonResponse(400, { error: "Missing code" });
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
    }
    return jsonResponse(200, {
      ok: true,
      rosterId: share.rosterId,
      role: share.role || "viewer",
      expiresAt: share.expiresAt ?? null,
      maxUses: share.maxUses ?? null,
      uses: share.uses ?? 0,
    });
  }

  if (method === "POST" && path === "/share/access-auth") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { code } = parseBody(event);
    if (!code) return jsonResponse(400, { error: "Missing code" });
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId: share.createdBy || userId,
      key: "share_access",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Share access limit reached for this billing period. Ask the roster owner to upgrade.",
        quota,
      });
    }

    if (share.role === "editor") {
      const canEdit = await ensurePaidPlanAccess(userId, "starter");
      if (!canEdit) {
        return jsonResponse(402, {
          error: "Subscription required",
          message:
            "Sign in with an active subscription to edit shared rosters.",
          requirePlan: "starter",
        });
      }
      const existing = await dynamodb
        .get({
          TableName: ROSTER_MEMBERS_TABLE,
          Key: { rosterId: share.rosterId, userId },
        })
        .promise();
      if (!existing.Item) {
        await dynamodb
          .put({
            TableName: ROSTER_MEMBERS_TABLE,
            Item: {
              rosterId: share.rosterId,
              userId,
              role: "editor",
              joinedAt: new Date().toISOString(),
            },
          })
          .promise();
      }
    }

    const incremented = await incrementShareUses(share);
    if (!incremented) {
      return jsonResponse(410, { error: "Share code exhausted" });
    }

    const roster = await dynamodb
      .get({ TableName: ROSTERS_TABLE, Key: { rosterId: share.rosterId } })
      .promise();
    const data = await dynamodb
      .get({ TableName: ROSTER_DATA_TABLE, Key: { rosterId: share.rosterId } })
      .promise();

    return jsonResponse(200, {
      rosterId: share.rosterId,
      role: share.role || "viewer",
      rosterName: roster.Item?.name ?? null,
      data: data.Item?.data ?? null,
      version: data.Item?.version ?? 0,
      last_modified: data.Item?.lastModified ?? null,
      last_modified_by: data.Item?.lastModifiedBy ?? null,
    });
  }

  if (method === "POST" && path === "/share/leave") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { code, startDate, endDate, notes, guestName } = parseBody(event);
    if (!code || !startDate) {
      return jsonResponse(400, { error: "Missing code or startDate" });
    }
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId: share.createdBy || userId,
      key: "share_leave",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Leave request limit reached for this billing period. Ask the roster owner to upgrade.",
        quota,
      });
    }

    const requestId = `${Date.now()}_guest_${code}`;
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: AVAILABILITY_REQUESTS_TABLE,
        Item: {
          rosterId: share.rosterId,
          requestId,
          userId: `guest:${code}`,
          type: "leave",
          startDate,
          endDate: endDate ?? startDate,
          status: "pending",
          notes: notes ?? "",
          guestName: guestName ?? "Guest",
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();

    await writeAuditLog({
      rosterId: share.rosterId,
      userId: `guest:${code}`,
      action: "guest_leave_requested",
      metadata: { requestId, guestName: guestName ?? "Guest" },
      timestamp: now,
    });

    return jsonResponse(200, { requestId });
  }

  if (method === "POST" && path === "/share/request") {
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const { code, startDate, endDate, notes, guestName, type } =
      parseBody(event);
    if (!code || !startDate) {
      return jsonResponse(400, { error: "Missing code or startDate" });
    }
    const allowedTypes = new Set([
      "leave",
      "training",
      "shift_change",
      "shiftChange",
      "swap",
      "general",
    ]);
    const normalizedType = allowedTypes.has(type) ? type : "general";
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId: share.createdBy || userId,
      key: "share_leave",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Request limit reached for this billing period. Ask the roster owner to upgrade.",
        quota,
      });
    }

    const requestId = `${Date.now()}_guest_${code}`;
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: AVAILABILITY_REQUESTS_TABLE,
        Item: {
          rosterId: share.rosterId,
          requestId,
          userId: `guest:${code}`,
          type: normalizedType,
          startDate,
          endDate: endDate ?? startDate,
          status: "pending",
          notes: notes ?? "",
          guestName: guestName ?? "Guest",
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();

    await writeAuditLog({
      rosterId: share.rosterId,
      userId: `guest:${code}`,
      action: "guest_request_submitted",
      metadata: {
        requestId,
        guestName: guestName ?? "Guest",
        type: normalizedType,
      },
      timestamp: now,
    });

    return jsonResponse(200, { requestId });
  }

  if (method === "POST" && path === "/orgs/create") {
    const hasAccess = await ensurePlanAccess(userId, "enterprise");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Enterprise to create organizations.",
      });
    }
    const { name } = parseBody(event);
    if (!name) return jsonResponse(400, { error: "Missing org name" });
    const orgId = Date.now().toString();
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: ORGS_TABLE,
        Item: {
          orgId,
          name,
          ownerId: userId,
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();
    await dynamodb
      .put({
        TableName: ORG_MEMBERS_TABLE,
        Item: {
          orgId,
          userId,
          role: "owner",
          joinedAt: now,
        },
      })
      .promise();
    return jsonResponse(200, { orgId });
  }

  if (method === "GET" && path === "/orgs") {
    const memberships = await dynamodb
      .query({
        TableName: ORG_MEMBERS_TABLE,
        IndexName: "userId-index",
        KeyConditionExpression: "userId = :userId",
        ExpressionAttributeValues: { ":userId": userId },
      })
      .promise();
    const orgIds = memberships.Items.map((m) => m.orgId);
    if (orgIds.length === 0) return jsonResponse(200, []);
    const batch = {
      RequestItems: {
        [ORGS_TABLE]: {
          Keys: orgIds.map((id) => ({ orgId: id })),
        },
      },
    };
    const orgs = await dynamodb.batchGet(batch).promise();
    const orgMap = new Map(
      (orgs.Responses[ORGS_TABLE] || []).map((o) => [o.orgId, o])
    );
    const result = memberships.Items.map((member) => {
      const org = orgMap.get(member.orgId);
      return {
        org_id: member.orgId,
        role: member.role,
        orgs: org
          ? {
              id: org.orgId,
              name: org.name,
              owner_id: org.ownerId,
              created_at: org.createdAt,
              updated_at: org.updatedAt,
            }
          : null,
      };
    });
    return jsonResponse(200, result);
  }

  if (method === "POST" && path === "/orgs/members/role") {
    const hasAccess = await ensurePlanAccess(userId, "enterprise");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Enterprise to manage org roles.",
      });
    }
    const { orgId, memberUserId, role } = parseBody(event);
    if (!orgId || !memberUserId || !role) {
      return jsonResponse(400, { error: "Missing orgId, memberUserId, or role" });
    }
    const canUpdate = await ensureOrgRole(orgId, userId, "admin");
    if (!canUpdate) return jsonResponse(403, { error: "Forbidden" });
    await dynamodb
      .update({
        TableName: ORG_MEMBERS_TABLE,
        Key: { orgId, userId: memberUserId },
        UpdateExpression: "SET #role = :role",
        ExpressionAttributeNames: { "#role": "role" },
        ExpressionAttributeValues: { ":role": role },
      })
      .promise();
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/teams/create") {
    const hasAccess = await ensurePlanAccess(userId, "enterprise");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Enterprise to create teams.",
      });
    }
    const { orgId, name } = parseBody(event);
    if (!orgId || !name) return jsonResponse(400, { error: "Missing orgId or name" });
    const canCreate = await ensureOrgRole(orgId, userId, "manager");
    if (!canCreate) return jsonResponse(403, { error: "Forbidden" });
    const teamId = Date.now().toString();
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: TEAMS_TABLE,
        Item: {
          orgId,
          teamId,
          name,
          createdAt: now,
        },
      })
      .promise();
    await dynamodb
      .put({
        TableName: TEAM_MEMBERS_TABLE,
        Item: {
          teamId,
          userId,
          role: "manager",
          joinedAt: now,
        },
      })
      .promise();
    return jsonResponse(200, { teamId });
  }

  if (method === "GET" && path === "/teams") {
    const orgId = event.queryStringParameters?.orgId;
    if (!orgId) return jsonResponse(400, { error: "Missing orgId" });
    const isMember = await ensureOrgRole(orgId, userId, "staff");
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: TEAMS_TABLE,
        KeyConditionExpression: "orgId = :orgId",
        ExpressionAttributeValues: { ":orgId": orgId },
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/teams/members/add") {
    const hasAccess = await ensurePlanAccess(userId, "enterprise");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Enterprise to add team members.",
      });
    }
    const { orgId, teamId, memberUserId, role } = parseBody(event);
    if (!orgId || !teamId || !memberUserId) {
      return jsonResponse(400, { error: "Missing orgId, teamId, or memberUserId" });
    }
    const team = await dynamodb
      .get({ TableName: TEAMS_TABLE, Key: { orgId, teamId } })
      .promise();
    if (!team.Item) {
      return jsonResponse(404, { error: "Team not found" });
    }
    const canAdd = await ensureOrgRole(orgId, userId, "manager");
    if (!canAdd) return jsonResponse(403, { error: "Forbidden" });
    await dynamodb
      .put({
        TableName: TEAM_MEMBERS_TABLE,
        Item: {
          teamId,
          userId: memberUserId,
          role: role ?? "member",
          joinedAt: new Date().toISOString(),
        },
      })
      .promise();
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/availability/request") {
    const { rosterId, type, startDate, endDate, notes } = parseBody(event);
    if (!rosterId || !type || !startDate) {
      return jsonResponse(400, { error: "Missing rosterId, type, or startDate" });
    }
    const canRequest = await ensureRosterRole(rosterId, userId, "member");
    if (!canRequest) return jsonResponse(403, { error: "Forbidden" });
    const requestId = `${Date.now()}_${userId}`;
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: AVAILABILITY_REQUESTS_TABLE,
        Item: {
          rosterId,
          requestId,
          userId,
          type,
          startDate,
          endDate: endDate ?? startDate,
          status: "pending",
          notes: notes ?? "",
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "availability_requested",
      metadata: { requestId, type },
      timestamp: now,
    });
    return jsonResponse(200, { requestId });
  }

  if (method === "GET" && path === "/availability/requests") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: AVAILABILITY_REQUESTS_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
        ScanIndexForward: false,
        Limit: 100,
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/availability/approve") {
    const { rosterId, requestId, decision, note } = parseBody(event);
    if (!rosterId || !requestId || !decision) {
      return jsonResponse(400, { error: "Missing rosterId, requestId, or decision" });
    }
    const canApprove = await ensureRosterRole(rosterId, userId, "manager");
    if (!canApprove) return jsonResponse(403, { error: "Forbidden" });
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: AVAILABILITY_REQUESTS_TABLE,
        Key: { rosterId, requestId },
        UpdateExpression:
          "SET #status = :status, #reviewedBy = :reviewedBy, #reviewNote = :note, #updatedAt = :updatedAt",
        ExpressionAttributeNames: {
          "#status": "status",
          "#reviewedBy": "reviewedBy",
          "#reviewNote": "reviewNote",
          "#updatedAt": "updatedAt",
        },
        ExpressionAttributeValues: {
          ":status": decision,
          ":reviewedBy": userId,
          ":note": note ?? "",
          ":updatedAt": now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "availability_reviewed",
      metadata: { requestId, decision },
      timestamp: now,
    });
    await publishNotification({
      subject: "Availability request reviewed",
      message: { rosterId, requestId, decision, reviewedBy: userId },
    });
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/swaps/request") {
    const { rosterId, fromPerson, toPerson, date, shift, notes } = parseBody(event);
    if (!rosterId || !fromPerson || !date) {
      return jsonResponse(400, { error: "Missing rosterId, fromPerson, or date" });
    }
    const canRequest = await ensureRosterRole(rosterId, userId, "member");
    if (!canRequest) return jsonResponse(403, { error: "Forbidden" });
    const requestId = `${Date.now()}_${userId}`;
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: SWAP_REQUESTS_TABLE,
        Item: {
          rosterId,
          requestId,
          userId,
          fromPerson,
          toPerson: toPerson ?? null,
          date,
          shift: shift ?? null,
          status: "pending",
          notes: notes ?? "",
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "swap_requested",
      metadata: { requestId, date },
      timestamp: now,
    });
    return jsonResponse(200, { requestId });
  }

  if (method === "GET" && path === "/swaps/requests") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: SWAP_REQUESTS_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
        ScanIndexForward: false,
        Limit: 100,
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/swaps/respond") {
    const { rosterId, requestId, decision, note } = parseBody(event);
    if (!rosterId || !requestId || !decision) {
      return jsonResponse(400, { error: "Missing rosterId, requestId, or decision" });
    }
    const canApprove = await ensureRosterRole(rosterId, userId, "manager");
    if (!canApprove) return jsonResponse(403, { error: "Forbidden" });
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: SWAP_REQUESTS_TABLE,
        Key: { rosterId, requestId },
        UpdateExpression:
          "SET #status = :status, #reviewedBy = :reviewedBy, #reviewNote = :note, #updatedAt = :updatedAt",
        ExpressionAttributeNames: {
          "#status": "status",
          "#reviewedBy": "reviewedBy",
          "#reviewNote": "reviewNote",
          "#updatedAt": "updatedAt",
        },
        ExpressionAttributeValues: {
          ":status": decision,
          ":reviewedBy": userId,
          ":note": note ?? "",
          ":updatedAt": now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "swap_reviewed",
      metadata: { requestId, decision },
      timestamp: now,
    });
    await publishNotification({
      subject: "Swap request reviewed",
      message: { rosterId, requestId, decision, reviewedBy: userId },
    });
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/locks/set") {
    const { rosterId, date, shift, personName, reason } = parseBody(event);
    if (!rosterId || !date || !shift) {
      return jsonResponse(400, { error: "Missing rosterId, date, or shift" });
    }
    const canLock = await ensureRosterRole(rosterId, userId, "manager");
    if (!canLock) return jsonResponse(403, { error: "Forbidden" });
    const lockId = `${date}_${shift}_${personName || "any"}`;
    await dynamodb
      .put({
        TableName: SHIFT_LOCKS_TABLE,
        Item: {
          rosterId,
          lockId,
          date,
          shift,
          personName: personName ?? null,
          reason: reason ?? "",
          lockedBy: userId,
          createdAt: new Date().toISOString(),
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "shift_locked",
      metadata: { lockId },
    });
    return jsonResponse(200, { lockId });
  }

  if (method === "GET" && path === "/locks") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: SHIFT_LOCKS_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
        ScanIndexForward: false,
        Limit: 200,
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/locks/remove") {
    const { rosterId, lockId } = parseBody(event);
    if (!rosterId || !lockId) {
      return jsonResponse(400, { error: "Missing rosterId or lockId" });
    }
    const canUnlock = await ensureRosterRole(rosterId, userId, "manager");
    if (!canUnlock) return jsonResponse(403, { error: "Forbidden" });
    await dynamodb
      .delete({
        TableName: SHIFT_LOCKS_TABLE,
        Key: { rosterId, lockId },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "shift_unlocked",
      metadata: { lockId },
    });
    return jsonResponse(200, { ok: true });
  }

  if (method === "POST" && path === "/proposals/create") {
    const { rosterId, title, description, changes } = parseBody(event);
    if (!rosterId || !title || !changes) {
      return jsonResponse(400, { error: "Missing rosterId, title, or changes" });
    }
    const canPropose = await ensureRosterRole(rosterId, userId, "member");
    if (!canPropose) return jsonResponse(403, { error: "Forbidden" });
    const proposalId = `${Date.now()}_${userId}`;
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: CHANGE_PROPOSALS_TABLE,
        Item: {
          rosterId,
          proposalId,
          userId,
          title,
          description: description ?? "",
          changes,
          status: "pending",
          createdAt: now,
          updatedAt: now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "proposal_created",
      metadata: { proposalId },
      timestamp: now,
    });
    return jsonResponse(200, { proposalId });
  }

  if (method === "GET" && path === "/proposals") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: CHANGE_PROPOSALS_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
        ScanIndexForward: false,
        Limit: 100,
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/proposals/resolve") {
    const { rosterId, proposalId, decision, note } = parseBody(event);
    if (!rosterId || !proposalId || !decision) {
      return jsonResponse(400, { error: "Missing rosterId, proposalId, or decision" });
    }
    const canResolve = await ensureRosterRole(rosterId, userId, "manager");
    if (!canResolve) return jsonResponse(403, { error: "Forbidden" });
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: CHANGE_PROPOSALS_TABLE,
        Key: { rosterId, proposalId },
        UpdateExpression:
          "SET #status = :status, #reviewedBy = :reviewedBy, #reviewNote = :note, #updatedAt = :updatedAt",
        ExpressionAttributeNames: {
          "#status": "status",
          "#reviewedBy": "reviewedBy",
          "#reviewNote": "reviewNote",
          "#updatedAt": "updatedAt",
        },
        ExpressionAttributeValues: {
          ":status": decision,
          ":reviewedBy": userId,
          ":note": note ?? "",
          ":updatedAt": now,
        },
      })
      .promise();
    await writeAuditLog({
      rosterId,
      userId,
      action: "proposal_resolved",
      metadata: { proposalId, decision },
      timestamp: now,
    });
    await publishNotification({
      subject: "Change proposal resolved",
      message: { rosterId, proposalId, decision, reviewedBy: userId },
    });
    return jsonResponse(200, { ok: true });
  }

  if (method === "GET" && path === "/audit") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const canView = await ensureRosterRole(rosterId, userId, "manager");
    if (!canView) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: AUDIT_LOGS_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
        ScanIndexForward: false,
        Limit: 200,
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/presence/heartbeat") {
    const { rosterId, device, displayName } = parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const now = new Date().toISOString();
    await dynamodb
      .put({
        TableName: PRESENCE_TABLE,
        Item: {
          rosterId,
          userId,
          displayName: displayName ?? getUserEmail(event) ?? "User",
          device: device ?? "unknown",
          lastSeen: now,
        },
      })
      .promise();
    return jsonResponse(200, { ok: true, lastSeen: now });
  }

  if (method === "GET" && path === "/presence/list") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: PRESENCE_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/timeclock/import") {
    const hasAccess = await ensurePlanAccess(userId, "operations");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Operations to import time clock data.",
      });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId,
      key: "timeclock",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Time clock import limit reached for this billing period. Upgrade to increase limits.",
        quota,
      });
    }
    const { rosterId, entries } = parseBody(event);
    if (!rosterId || !Array.isArray(entries)) {
      return jsonResponse(400, { error: "Missing rosterId or entries" });
    }
    const canImport = await ensureRosterRole(rosterId, userId, "manager");
    if (!canImport) return jsonResponse(403, { error: "Forbidden" });

    const prepared = entries.map((entry) => {
      const entryId =
        entry.entryId || `${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
      return {
        rosterId,
        entryId,
        personName: entry.personName ?? "Unknown",
        date: entry.date,
        hours: entry.hours ?? 0,
        source: entry.source ?? "import",
        createdAt: new Date().toISOString(),
        importedBy: userId,
      };
    });

    const batches = chunkArray(prepared, 25);
    for (const batch of batches) {
      await dynamodb
        .batchWrite({
          RequestItems: {
            [TIME_CLOCK_TABLE]: batch.map((item) => ({
              PutRequest: { Item: item },
            })),
          },
        })
        .promise();
    }

    await writeAuditLog({
      rosterId,
      userId,
      action: "timeclock_imported",
      metadata: { count: prepared.length },
    });

    return jsonResponse(200, { imported: prepared.length });
  }

  if (method === "GET" && path === "/timeclock") {
    const rosterId = event.queryStringParameters?.rosterId;
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const query = await dynamodb
      .query({
        TableName: TIME_CLOCK_TABLE,
        KeyConditionExpression: "rosterId = :rosterId",
        ExpressionAttributeValues: { ":rosterId": rosterId },
        ScanIndexForward: false,
        Limit: 200,
      })
      .promise();
    return jsonResponse(200, query.Items || []);
  }

  if (method === "POST" && path === "/analytics/track") {
    const hasAccess = await ensurePlanAccess(userId, "operations");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Operations to use analytics.",
      });
    }
    const body = parseBody(event);
    const rawEvents = Array.isArray(body.events)
      ? body.events
      : body.event
      ? [body.event]
      : [];
    if (rawEvents.length === 0) {
      return jsonResponse(400, { error: "Missing analytics events" });
    }

    const acceptedItems = [];
    let rejected = 0;
    for (const raw of rawEvents) {
      const rosterId = raw.rosterId || (userId ? `user#${userId}` : null);
      if (!rosterId) {
        rejected += 1;
        continue;
      }
      if (!rosterId.startsWith("user#")) {
        const hasAccess = await ensureRosterAccess(rosterId, userId);
        if (!hasAccess) {
          rejected += 1;
          continue;
        }
      }
      const eventId =
        raw.id || `${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
      acceptedItems.push({
        rosterId,
        eventId,
        userId: userId ?? raw.userId ?? "unknown",
        name: raw.name || "event",
        type: raw.type || "custom",
        timestamp: raw.timestamp || new Date().toISOString(),
        sessionId: raw.sessionId ?? null,
        properties: raw.properties ?? {},
      });
    }

    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId,
      key: "analytics",
      amount: acceptedItems.length || 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "Analytics limit reached for this billing period. Upgrade to increase limits.",
        quota,
      });
    }

    const accepted = await writeAnalyticsEvents(acceptedItems);
    return jsonResponse(200, {
      accepted,
      rejected: rejected + (acceptedItems.length - accepted),
    });
  }

  if (method === "POST" && path === "/analytics/track-public") {
    if (!isAllowedMarketingOrigin(event)) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const body = parseBody(event);
    const rawEvents = Array.isArray(body.events)
      ? body.events
      : body.event
      ? [body.event]
      : [];
    if (rawEvents.length === 0) {
      return jsonResponse(400, { error: "Missing analytics events" });
    }
    const acceptedItems = [];
    let rejected = 0;
    const limit = Math.min(rawEvents.length, 50);
    for (let i = 0; i < limit; i += 1) {
      const raw = rawEvents[i];
      const props = raw.properties ?? {};
      if (props.source !== "website" && props.platform !== "website") {
        rejected += 1;
        continue;
      }
      const eventId =
        raw.id || `${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
      const anonId = props.anonId || raw.userId || "anon";
      acceptedItems.push({
        rosterId: "website",
        eventId,
        userId: anonId,
        name: raw.name || "event",
        type: raw.type || "custom",
        timestamp: raw.timestamp || new Date().toISOString(),
        sessionId: raw.sessionId ?? null,
        properties: {
          ...props,
          source: "website",
          platform: "website",
        },
      });
    }
    const accepted = await writeAnalyticsEvents(acceptedItems);
    return jsonResponse(200, {
      accepted,
      rejected: rejected + (acceptedItems.length - accepted),
    });
  }

  if (method === "POST" && path === "/ai/feedback") {
    const { rosterId, suggestionId, feedback, impact, notes } = parseBody(event);
    if (!rosterId || !suggestionId || !feedback) {
      return jsonResponse(400, { error: "Missing rosterId, suggestionId, or feedback" });
    }
    const isMember = await ensureRosterAccess(rosterId, userId);
    if (!isMember) return jsonResponse(403, { error: "Forbidden" });
    const feedbackId = `${Date.now()}_${userId}`;
    await dynamodb
      .put({
        TableName: AI_FEEDBACK_TABLE,
        Item: {
          rosterId,
          feedbackId,
          suggestionId,
          feedback,
          impact: impact ?? null,
          notes: notes ?? "",
          userId,
          createdAt: new Date().toISOString(),
        },
      })
      .promise();
    return jsonResponse(200, { ok: true });
  }

  if (method === "GET" && path === "/admin/metrics") {
    if (!(await isAdminUserAsync(event))) {
      return jsonResponse(403, { error: "Admin access required" });
    }
    const data = await getAdminMetricsData();
    return jsonResponse(200, data);
  }

  if (method === "GET" && path === "/admin/usage/user") {
    if (!(await isAdminUserAsync(event))) {
      return jsonResponse(403, { error: "Admin access required" });
    }
    const email = (event.queryStringParameters?.email || "").toString().trim();
    const userId =
      (event.queryStringParameters?.userId || "").toString().trim();
    let profile = null;
    if (email) {
      profile = await findProfileByEmail(email.toLowerCase(), email);
    } else if (userId) {
      profile = await getUserProfile(userId);
    }
    if (!profile) {
      return jsonResponse(404, { error: "User profile not found" });
    }
    const config = await getRuntimeConfig();
    return jsonResponse(200, {
      userId: profile.userId,
      email: profile.email || "",
      plan: profile.subscriptionPlan || "none",
      status: profile.subscriptionStatus || "inactive",
      usageLimits: profile.usageLimits || {},
      usageSnapshot: buildUsageSnapshot(profile, config),
    });
  }

  if (method === "POST" && path === "/admin/usage/limits") {
    if (!(await isAdminUserAsync(event))) {
      return jsonResponse(403, { error: "Admin access required" });
    }
    if (!USER_PROFILES_TABLE) {
      return jsonResponse(500, { error: "User profiles table not configured" });
    }
    const { userId, email, limits } = parseBody(event);
    const rawEmail = (email || "").toString().trim();
    let profile = null;
    if (rawEmail) {
      profile = await findProfileByEmail(rawEmail.toLowerCase(), rawEmail);
    } else if (userId) {
      profile = await getUserProfile(userId);
    }
    if (!profile?.userId) {
      return jsonResponse(404, { error: "User profile not found" });
    }
    const nextLimits =
      limits && typeof limits === "object" ? limits : {};
    const now = new Date().toISOString();
    await dynamodb
      .update({
        TableName: USER_PROFILES_TABLE,
        Key: { userId: profile.userId },
        UpdateExpression:
          "SET #usageLimits = :limits, #updatedAt = :updatedAt",
        ExpressionAttributeNames: {
          "#usageLimits": "usageLimits",
          "#updatedAt": "updatedAt",
        },
        ExpressionAttributeValues: {
          ":limits": nextLimits,
          ":updatedAt": now,
        },
      })
      .promise();
    const config = await getRuntimeConfig();
    const refreshed = await getUserProfile(profile.userId);
    return jsonResponse(200, {
      ok: true,
      userId: profile.userId,
      email: profile.email || rawEmail,
      usageLimits: nextLimits,
      usageSnapshot: buildUsageSnapshot(refreshed || profile, config),
    });
  }

  if (method === "GET" && path === "/admin/trial-history") {
    if (!(await isAdminUserAsync(event))) {
      return jsonResponse(403, { error: "Admin access required" });
    }
    const email = (event.queryStringParameters?.email || "").toString().trim();
    if (!email) {
      return jsonResponse(400, { error: "Missing email" });
    }
    const emailLower = email.toLowerCase();
    const record = await getTrialHistoryRecord(emailLower);
    const profile = await findProfileByEmail(emailLower, email);
    return jsonResponse(200, {
      email,
      emailLower,
      hasTrialHistory: Boolean(record),
      trialHistory: record || null,
      profile: profile
        ? {
            userId: profile.userId || null,
            trialStartAt: profile.trialStartAt || null,
            trialExpiresAt: profile.trialExpiresAt || null,
            subscriptionStatus: profile.subscriptionStatus || null,
            subscriptionPlan: profile.subscriptionPlan || null,
          }
        : null,
    });
  }

  if (method === "POST" && path === "/admin/trial-history/reset") {
    if (!(await isAdminUserAsync(event))) {
      return jsonResponse(403, { error: "Admin access required" });
    }
    if (!TRIAL_HISTORY_TABLE) {
      return jsonResponse(500, { error: "Trial history not configured" });
    }
    const { email } = parseBody(event);
    const rawEmail = (email || "").toString().trim();
    if (!rawEmail) {
      return jsonResponse(400, { error: "Missing email" });
    }
    const emailLower = rawEmail.toLowerCase();
    let deleted = false;
    try {
      await dynamodb
        .delete({
          TableName: TRIAL_HISTORY_TABLE,
          Key: { emailLower },
        })
        .promise();
      deleted = true;
    } catch (err) {
      console.warn("Trial history delete failed", err);
    }
    return jsonResponse(200, {
      ok: true,
      email: rawEmail,
      emailLower,
      deleted,
    });
  }

  if (method === "POST" && path === "/admin/share/revoke-all") {
    if (!(await isAdminUserAsync(event))) {
      return jsonResponse(403, { error: "Admin access required" });
    }
    if (!SHARE_CODES_TABLE) {
      return jsonResponse(503, { error: "Share codes unavailable" });
    }
    const adminId = getUserId(event) || "admin";
    let lastKey;
    let scanned = 0;
    let revoked = 0;
    do {
      const response = await dynamodb
        .scan({
          TableName: SHARE_CODES_TABLE,
          ProjectionExpression: "code, #status",
          ExpressionAttributeNames: { "#status": "status" },
          ExclusiveStartKey: lastKey,
        })
        .promise();
      const items = response.Items || [];
      scanned += items.length;
      for (const item of items) {
        if (!item.code) continue;
        const status = (item.status || "active").toString().toLowerCase();
        if (status === "revoked") continue;
        await dynamodb
          .update({
            TableName: SHARE_CODES_TABLE,
            Key: { code: item.code },
            UpdateExpression:
              "SET #status = :status, revokedAt = :revokedAt, revokedBy = :revokedBy",
            ExpressionAttributeNames: { "#status": "status" },
            ExpressionAttributeValues: {
              ":status": "revoked",
              ":revokedAt": new Date().toISOString(),
              ":revokedBy": adminId,
            },
          })
          .promise();
        revoked += 1;
      }
      lastKey = response.LastEvaluatedKey;
    } while (lastKey);
    return jsonResponse(200, { scanned, revoked });
  }

  if (method === "GET" && path === "/roles/templates") {
    const templates = [
      {
        id: "owner",
        name: "Owner",
        description: "Full control including billing and role management.",
        permissions: [
          "roster.read",
          "roster.write",
          "roster.manage",
          "org.manage",
          "team.manage",
          "settings.manage",
        ],
      },
      {
        id: "admin",
        name: "Admin",
        description: "Manage rosters, teams, and approvals.",
        permissions: [
          "roster.read",
          "roster.write",
          "roster.manage",
          "team.manage",
          "approvals.manage",
        ],
      },
      {
        id: "manager",
        name: "Manager",
        description: "Approve requests and manage day-to-day roster.",
        permissions: [
          "roster.read",
          "roster.write",
          "approvals.manage",
          "coverage.manage",
        ],
      },
      {
        id: "member",
        name: "Staff",
        description: "Read roster and submit requests.",
        permissions: ["roster.read", "requests.submit"],
      },
      {
        id: "viewer",
        name: "Viewer",
        description: "Read-only access.",
        permissions: ["roster.read"],
      },
    ];
    return jsonResponse(200, templates);
  }

  if (method === "POST" && path === "/ai/suggestions") {
    const hasAccess = await ensurePlanAccess(userId, "operations");
    if (!hasAccess) {
      return jsonResponse(402, {
        error: "Subscription required",
        message: "Upgrade to Operations to unlock AI suggestions.",
      });
    }
    const config = await getRuntimeConfig();
    const quota = await consumeQuota({
      userId,
      key: "ai",
      amount: 1,
      config,
    });
    if (!quota.allowed) {
      return jsonResponse(402, {
        error: "Quota exceeded",
        message:
          "AI usage limit reached for this billing period. Upgrade to increase limits.",
        quota,
      });
    }
    const body = parseBody(event);
    try {
      const result = await invokeBedrock(body);
      const suggestions = Array.isArray(result?.suggestions)
        ? result.suggestions
        : [];
      return jsonResponse(200, { suggestions });
    } catch (error) {
      console.error("Bedrock invoke error", error);
      return jsonResponse(200, { suggestions: [] });
    }
  }

  return jsonResponse(404, { error: "Not found" });
};

