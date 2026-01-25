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
  EXPORTS_BUCKET,
  CLOUDFRONT_URL,
  SNS_TOPIC_ARN,
  SES_FROM,
  USER_PROFILES_TABLE,
  ROSTER_SALT,
  BEDROCK_MODEL_ID,
  USER_POOL_ID,
} = process.env;

const jsonResponse = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
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

const getUserId = (event) =>
  event?.requestContext?.authorizer?.jwt?.claims?.sub ||
  event?.requestContext?.authorizer?.iam?.cognitoIdentity?.identityId ||
  event?.requestContext?.identity?.cognitoIdentityId ||
  null;

const getUserEmail = (event) =>
  event?.requestContext?.authorizer?.jwt?.claims?.email || null;

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
  if (!code) return null;
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

const sendEmail = async ({ to, subject, body }) => {
  if (!SES_FROM || !to) return;
  await ses
    .sendEmail({
      Source: SES_FROM,
      Destination: { ToAddresses: [to] },
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
  const modelId =
    BEDROCK_MODEL_ID || "anthropic.claude-3-haiku-20240307-v1:0";
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

const batchDelete = async (tableName, keys) => {
  if (!keys.length) return;
  const chunks = [];
  for (let i = 0; i < keys.length; i += 25) {
    chunks.push(keys.slice(i, i + 25));
  }
  for (const chunk of chunks) {
    await dynamodb
      .batchWrite({
        RequestItems: {
          [tableName]: chunk.map((key) => ({
            DeleteRequest: { Key: key },
          })),
        },
      })
      .promise();
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

  const openRoutes = new Set(["/health", "/share/access", "/share/leave"]);
  if (path === "/health") {
    return jsonResponse(200, { ok: true });
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
      const query = await dynamodb
        .query({
          TableName: tableName,
          KeyConditionExpression: "rosterId = :rosterId",
          ExpressionAttributeValues: { ":rosterId": rosterId },
        })
        .promise();
      const items = query.Items || [];
      if (!items.length) return;
      await batchDelete(
        tableName,
        items.map((item) => {
          const key = { rosterId };
          if (rangeKey) key[rangeKey] = item[rangeKey];
          return key;
        })
      );
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

  if (method === "POST" && path === "/roster/save") {
    const { rosterId, data } = parseBody(event);
    if (!rosterId || !data) {
      return jsonResponse(400, { error: "Missing rosterId or data" });
    }
    const canEdit = await ensureRosterRole(rosterId, userId, "member");
    if (!canEdit) {
      return jsonResponse(403, { error: "Forbidden" });
    }
    const now = new Date().toISOString();
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

    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_saved",
      metadata: { version: update.Attributes.version },
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
    await writeAuditLog({
      rosterId,
      userId,
      action: "roster_update",
      metadata: { updateId },
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

  if (method === "POST" && path === "/exports/roster") {
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
    const { rosterId, role, expiresInHours, maxUses, customCode } =
      parseBody(event);
    if (!rosterId) return jsonResponse(400, { error: "Missing rosterId" });
    const canShare = await ensureRosterRole(rosterId, userId, "manager");
    if (!canShare) return jsonResponse(403, { error: "Forbidden" });

    const safeRole = role === "editor" ? "editor" : "viewer";
    const now = new Date().toISOString();
    const expiresAt =
      typeof expiresInHours === "number"
        ? new Date(Date.now() + expiresInHours * 3600 * 1000).toISOString()
        : null;

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
          maxUses: maxUses ?? null,
          uses: 0,
        },
      })
      .promise();

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
      maxUses: maxUses ?? null,
    });
  }

  if (method === "POST" && path === "/share/access") {
    const { code } = parseBody(event);
    if (!code) return jsonResponse(400, { error: "Missing code" });
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
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

  if (method === "POST" && path === "/share/access-auth") {
    const { code } = parseBody(event);
    if (!code) return jsonResponse(400, { error: "Missing code" });
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
    }

    if (share.role === "editor") {
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
    const { code, startDate, endDate, notes, guestName } = parseBody(event);
    if (!code || !startDate) {
      return jsonResponse(400, { error: "Missing code or startDate" });
    }
    const share = await loadShareCode(code);
    const validation = validateShareCode(share);
    if (!validation.ok) {
      return jsonResponse(validation.status, { error: validation.error });
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

  if (method === "POST" && path === "/orgs/create") {
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
