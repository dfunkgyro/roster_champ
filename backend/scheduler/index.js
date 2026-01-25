const AWS = require("aws-sdk");

const dynamodb = new AWS.DynamoDB.DocumentClient();
const sns = new AWS.SNS();

const {
  AVAILABILITY_REQUESTS_TABLE,
  SWAP_REQUESTS_TABLE,
  CHANGE_PROPOSALS_TABLE,
  SNS_TOPIC_ARN,
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

exports.handler = async () => {
  if (!SNS_TOPIC_ARN) {
    return { ok: false, reason: "SNS_TOPIC_ARN not configured" };
  }

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
