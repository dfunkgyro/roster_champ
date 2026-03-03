const AWS = require("aws-sdk");

const dynamodb = new AWS.DynamoDB.DocumentClient();
const cognito = new AWS.CognitoIdentityServiceProvider();

const TRIAL_HISTORY_TABLE = process.env.TRIAL_HISTORY_TABLE || "";

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
          source: source || "post_confirmation",
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

const findProfileByEmail = async (tableName, email) => {
  const normalized = (email || "").toLowerCase().trim();
  if (!normalized) return null;
  let lastKey = null;
  do {
    const response = await dynamodb
      .scan({
        TableName: tableName,
        FilterExpression: "#email = :emailRaw OR #emailLower = :emailLower",
        ExpressionAttributeNames: {
          "#email": "email",
          "#emailLower": "emailLower",
        },
        ExpressionAttributeValues: {
          ":emailRaw": email,
          ":emailLower": normalized,
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

exports.handler = async (event) => {
  try {
    const tableName = process.env.USER_PROFILES_TABLE;
    if (!tableName) {
      console.error("Missing USER_PROFILES_TABLE env var.");
      return event;
    }

    const attrs = event.request?.userAttributes || {};
    const userId = attrs.sub || event.userName;
    if (!userId) {
      console.error("Missing userId on post confirmation event.");
      return event;
    }

    const now = new Date().toISOString();
    const email = attrs.email || null;
    const name = attrs.name || attrs.given_name || null;

    let providers = [];
    if (attrs.identities) {
      try {
        const identities = JSON.parse(attrs.identities);
        if (Array.isArray(identities)) {
          providers = identities
            .map((identity) => identity.providerName)
            .filter(Boolean);
        }
      } catch (err) {
        console.warn("Failed to parse identities attribute", err);
      }
    }
    if (providers.length === 0) {
      providers = ["cognito"];
    }

    const normalizedEmail = (email || "").toLowerCase().trim();
    const prior = await findProfileByEmail(tableName, email);
    const trialStartAt = now;
    const trialExpiresAt = new Date(
      Date.now() + 7 * 24 * 60 * 60 * 1000
    ).toISOString();
    const trialHistory = await getTrialHistoryRecord(normalizedEmail);
    const trialEligible = (!prior || !prior.trialStartAt) && !trialHistory;

    const item = {
      userId,
      email,
      emailLower: normalizedEmail,
      name,
      providers,
      status: "active",
      subscriptionStatus: trialEligible ? "trialing" : "inactive",
      subscriptionPlan: trialEligible ? "trial" : "none",
      ...(trialEligible ? { trialStartAt, trialExpiresAt } : {}),
      createdAt: now,
      updatedAt: now,
    };

    try {
      await dynamodb
        .put({
          TableName: tableName,
          Item: item,
          ConditionExpression: "attribute_not_exists(userId)",
        })
        .promise();
    } catch (err) {
      if (err.code === "ConditionalCheckFailedException") {
        await dynamodb
          .update({
            TableName: tableName,
            Key: { userId },
            UpdateExpression:
              "SET #email = if_not_exists(#email, :email), #emailLower = if_not_exists(#emailLower, :emailLower), #name = if_not_exists(#name, :name), #providers = if_not_exists(#providers, :providers), #status = if_not_exists(#status, :status), subscriptionStatus = if_not_exists(subscriptionStatus, :subscriptionStatus), subscriptionPlan = if_not_exists(subscriptionPlan, :subscriptionPlan), trialStartAt = if_not_exists(trialStartAt, :trialStartAt), trialExpiresAt = if_not_exists(trialExpiresAt, :trialExpiresAt), updatedAt = :updatedAt",
            ExpressionAttributeNames: {
              "#email": "email",
              "#emailLower": "emailLower",
              "#name": "name",
              "#providers": "providers",
              "#status": "status",
            },
            ExpressionAttributeValues: {
              ":email": email,
              ":emailLower": normalizedEmail,
              ":name": name,
              ":providers": providers,
              ":status": "active",
              ":subscriptionStatus": trialEligible ? "trialing" : "inactive",
              ":subscriptionPlan": trialEligible ? "trial" : "none",
              ":trialStartAt": trialEligible ? trialStartAt : null,
              ":trialExpiresAt": trialEligible ? trialExpiresAt : null,
              ":updatedAt": now,
            },
          })
          .promise();
      } else {
        throw err;
      }
    }

    if (trialEligible && normalizedEmail) {
      await recordTrialHistory({
        emailLower: normalizedEmail,
        email,
        userId,
        source: "post_confirmation",
      });
    }

    if (event.userPoolId && event.userName) {
      try {
        await cognito
          .adminAddUserToGroup({
            UserPoolId: event.userPoolId,
            Username: event.userName,
            GroupName: "Users",
          })
          .promise();
      } catch (err) {
        if (err.code !== "ResourceNotFoundException") {
          console.warn("Failed to add user to Users group", err);
        }
      }
    }
  } catch (err) {
    console.error("postConfirmation error", err);
  }

  return event;
};
