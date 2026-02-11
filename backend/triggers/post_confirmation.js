const AWS = require("aws-sdk");

const dynamodb = new AWS.DynamoDB.DocumentClient();

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

    const item = {
      userId,
      email,
      name,
      providers,
      status: "active",
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
              "SET #email = if_not_exists(#email, :email), #name = if_not_exists(#name, :name), #providers = if_not_exists(#providers, :providers), #status = if_not_exists(#status, :status), updatedAt = :updatedAt",
            ExpressionAttributeNames: {
              "#email": "email",
              "#name": "name",
              "#providers": "providers",
              "#status": "status",
            },
            ExpressionAttributeValues: {
              ":email": email,
              ":name": name,
              ":providers": providers,
              ":status": "active",
              ":updatedAt": now,
            },
          })
          .promise();
      } else {
        throw err;
      }
    }
  } catch (err) {
    console.error("postConfirmation error", err);
  }

  return event;
};
