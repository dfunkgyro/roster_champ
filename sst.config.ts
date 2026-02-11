export default $config({
  app(input) {
    return {
      name: "roster-champ",
      region: "us-east-1",
      stage: input.stage ?? "dev",
      home: "aws",
    };
  },
  async run() {
    const aws = await import("@pulumi/aws");
    const pulumi = await import("@pulumi/pulumi");
    const random = await import("@pulumi/random");
    const path = await import("path");
    const fs = await import("fs");
    const esbuild = await import("esbuild");

    const region = aws.config.region ?? "us-east-1";
    const stageName = process.env.SST_STAGE ?? "dev";

    const kmsKey = new aws.kms.Key("roster-data-key", {
      description: "Roster Champ data encryption key",
      deletionWindowInDays: 7,
    });

    const userProfilesTable = new aws.dynamodb.Table("user-profiles", {
      attributes: [{ name: "userId", type: "S" }],
      hashKey: "userId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const appSecrets = new aws.secretsmanager.Secret("roster-app-secrets", {
      name: `roster-app-secrets-${stageName}`,
    });

    const appSecretsPayload = {
      sesFrom: process.env.SES_FROM ?? "",
      bedrockModelId:
        process.env.BEDROCK_MODEL_ID ?? "anthropic.claude-3-haiku-20240307-v1:0",
      updateUrls: {
        default: process.env.UPDATE_URL ?? "",
        android: process.env.UPDATE_URL_ANDROID ?? "",
        windows: process.env.UPDATE_URL_WINDOWS ?? "",
        linux: process.env.UPDATE_URL_LINUX ?? "",
        ios: process.env.UPDATE_URL_IOS ?? "",
        macos: process.env.UPDATE_URL_MACOS ?? "",
      },
      minVersions: {
        default: process.env.MIN_APP_VERSION ?? "",
        android: process.env.MIN_APP_VERSION_ANDROID ?? "",
        windows: process.env.MIN_APP_VERSION_WINDOWS ?? "",
        linux: process.env.MIN_APP_VERSION_LINUX ?? "",
        ios: process.env.MIN_APP_VERSION_IOS ?? "",
        macos: process.env.MIN_APP_VERSION_MACOS ?? "",
      },
      latestVersions: {
        default: process.env.LATEST_APP_VERSION ?? "",
        android: process.env.LATEST_APP_VERSION_ANDROID ?? "",
        windows: process.env.LATEST_APP_VERSION_WINDOWS ?? "",
        linux: process.env.LATEST_APP_VERSION_LINUX ?? "",
        ios: process.env.LATEST_APP_VERSION_IOS ?? "",
        macos: process.env.LATEST_APP_VERSION_MACOS ?? "",
      },
    };

    new aws.secretsmanager.SecretVersion("roster-app-secrets-version", {
      secretId: appSecrets.id,
      secretString: JSON.stringify(appSecretsPayload),
    });

    const distRoot = path.resolve(process.cwd(), "backend/.dist");
    const apiOutDir = path.join(distRoot, "api");
    const schedulerOutDir = path.join(distRoot, "scheduler");
    const triggersOutDir = path.join(distRoot, "triggers");
    fs.mkdirSync(apiOutDir, { recursive: true });
    fs.mkdirSync(schedulerOutDir, { recursive: true });
    fs.mkdirSync(triggersOutDir, { recursive: true });

    const postConfirmRole = new aws.iam.Role("post-confirm-role", {
      assumeRolePolicy: aws.iam.assumeRolePolicyForPrincipal({
        Service: "lambda.amazonaws.com",
      }),
    });

    new aws.iam.RolePolicyAttachment("post-confirm-basic", {
      role: postConfirmRole.name,
      policyArn: aws.iam.ManagedPolicies.AWSLambdaBasicExecutionRole,
    });

    new aws.iam.RolePolicy("post-confirm-policy", {
      role: postConfirmRole.id,
      policy: userProfilesTable.arn.apply((profilesArn) =>
        JSON.stringify({
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"],
              Resource: profilesArn,
            },
          ],
        })
      ),
    });

    const postConfirmHandlerPath = path.resolve(
      process.cwd(),
      "backend/triggers/post_confirmation.js"
    );
    const postConfirmBundlePath = path.join(triggersOutDir, "post_confirmation.js");
    await esbuild.build({
      entryPoints: [postConfirmHandlerPath],
      bundle: true,
      platform: "node",
      target: ["node18"],
      outfile: postConfirmBundlePath,
    });

    const postConfirmFunction = new aws.lambda.Function("post-confirmation", {
      runtime: "nodejs18.x",
      role: postConfirmRole.arn,
      handler: "post_confirmation.handler",
      code: new pulumi.asset.AssetArchive({
        "post_confirmation.js": new pulumi.asset.FileAsset(postConfirmBundlePath),
      }),
      environment: {
        variables: {
          USER_PROFILES_TABLE: userProfilesTable.name,
        },
      },
    });

    const userPool = new aws.cognito.UserPool("roster-user-pool", {
      autoVerifiedAttributes: ["email"],
      usernameAttributes: ["email"],
      lambdaConfig: {
        postConfirmation: postConfirmFunction.arn,
      },
    });

    const domainSuffix = new random.RandomString("roster-domain-suffix", {
      length: 8,
      special: false,
      upper: false,
    });

    const customDomainEnv = process.env.COGNITO_CUSTOM_DOMAIN?.trim();
    const disableCustomDomain =
      (process.env.COGNITO_CUSTOM_DOMAIN_DISABLED ?? "").toLowerCase() === "true" ||
      process.env.COGNITO_CUSTOM_DOMAIN_DISABLED === "1";
    const keepCertOnDisable =
      (process.env.COGNITO_CUSTOM_DOMAIN_KEEP_CERT ?? "").toLowerCase() === "true" ||
      process.env.COGNITO_CUSTOM_DOMAIN_KEEP_CERT === "1";
    const customDomain = disableCustomDomain
      ? ""
      : customDomainEnv && customDomainEnv.length > 0
          ? customDomainEnv
          : "auth.rosterchampion.com";
    let validationOptions: pulumi.Output<
      aws.types.output.acm.CertificateDomainValidationOption[] | undefined
    > | undefined;

    let userPoolDomain: aws.cognito.UserPoolDomain;
    if (customDomain) {
      const cert = new aws.acm.Certificate(
        "roster-custom-domain-cert",
        {
          domainName: customDomain,
          validationMethod: "DNS",
        },
        {
          protect: true,
        }
      );
      validationOptions = cert.domainValidationOptions;
      userPoolDomain = new aws.cognito.UserPoolDomain(
        "roster-user-pool-domain",
        {
          domain: customDomain,
          userPoolId: userPool.id,
          certificateArn: cert.arn,
        }
      );
    } else {
      if (keepCertOnDisable) {
        new aws.acm.Certificate(
          "roster-custom-domain-cert",
          {
            domainName: customDomainEnv && customDomainEnv.length > 0
              ? customDomainEnv
              : "auth.rosterchampion.com",
            validationMethod: "DNS",
          },
          {
            protect: true,
          }
        );
      }
      userPoolDomain = new aws.cognito.UserPoolDomain(
        "roster-user-pool-domain",
        {
          domain: pulumi.interpolate`roster-${stageName}-${domainSuffix.result}`,
          userPoolId: userPool.id,
        }
      );
    }

    new aws.lambda.Permission("post-confirmation-permission", {
      action: "lambda:InvokeFunction",
      function: postConfirmFunction.name,
      principal: "cognito-idp.amazonaws.com",
      sourceArn: userPool.arn,
    });

    const redirectUris = [
      "rosterchamp://auth",
      "http://127.0.0.1:53682/",
      "http://localhost:53682/",
    ];

    const googleClientId =
      process.env.GOOGLE_OAUTH_CLIENT_ID?.trim() ?? "";
    const googleClientSecret =
      process.env.GOOGLE_OAUTH_CLIENT_SECRET?.trim() ?? "";

    const supportedProviders: string[] = ["COGNITO"];

    if (googleClientId && googleClientSecret) {
      const googleProvider = new aws.cognito.IdentityProvider(
        "roster-google-idp",
        {
          userPoolId: userPool.id,
          providerName: "Google",
          providerType: "Google",
          providerDetails: {
            client_id: googleClientId,
            client_secret: googleClientSecret,
            authorize_scopes: "openid email profile",
          },
          attributeMapping: {
            email: "email",
            username: "sub",
            given_name: "given_name",
            family_name: "family_name",
            name: "name",
          },
        }
      );
      supportedProviders.push(googleProvider.providerName);
    }

    const userPoolClient = new aws.cognito.UserPoolClient(
      "roster-user-pool-client",
      {
        userPoolId: userPool.id,
        generateSecret: false,
        allowedOauthFlows: ["code"],
        allowedOauthFlowsUserPoolClient: true,
        allowedOauthScopes: ["openid", "email", "profile"],
        supportedIdentityProviders: supportedProviders,
        callbackUrls: redirectUris,
        logoutUrls: redirectUris,
        explicitAuthFlows: [
          "ALLOW_USER_PASSWORD_AUTH",
          "ALLOW_USER_SRP_AUTH",
          "ALLOW_REFRESH_TOKEN_AUTH",
        ],
      }
    );

    const identityPool = new aws.cognito.IdentityPool("roster-identity-pool", {
      identityPoolName: `roster-identity-${stageName}`,
      allowUnauthenticatedIdentities: false,
      cognitoIdentityProviders: [
        {
          clientId: userPoolClient.id,
          providerName: pulumi.interpolate`cognito-idp.${region}.amazonaws.com/${userPool.id}`,
        },
      ],
      supportedLoginProviders: undefined,
    });

    const authenticatedRole = new aws.iam.Role("identity-auth-role", {
      assumeRolePolicy: identityPool.id.apply((id) =>
        JSON.stringify({
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Principal: { Federated: "cognito-identity.amazonaws.com" },
              Action: "sts:AssumeRoleWithWebIdentity",
              Condition: {
                StringEquals: {
                  "cognito-identity.amazonaws.com:aud": id,
                },
                "ForAnyValue:StringLike": {
                  "cognito-identity.amazonaws.com:amr": "authenticated",
                },
              },
            },
          ],
        })
      ),
    });

    const rostersTable = new aws.dynamodb.Table("rosters", {
      attributes: [{ name: "rosterId", type: "S" }],
      hashKey: "rosterId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const rosterMembersTable = new aws.dynamodb.Table("roster-members", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "userId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "userId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
      globalSecondaryIndexes: [
        {
          name: "userId-index",
          hashKey: "userId",
          projectionType: "ALL",
        },
      ],
    });

    const rosterDataTable = new aws.dynamodb.Table("roster-data", {
      attributes: [{ name: "rosterId", type: "S" }],
      hashKey: "rosterId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const rosterUpdatesTable = new aws.dynamodb.Table("roster-updates", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "updateId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "updateId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const orgsTable = new aws.dynamodb.Table("orgs", {
      attributes: [{ name: "orgId", type: "S" }],
      hashKey: "orgId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const orgMembersTable = new aws.dynamodb.Table("org-members", {
      attributes: [
        { name: "orgId", type: "S" },
        { name: "userId", type: "S" },
      ],
      hashKey: "orgId",
      rangeKey: "userId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
      globalSecondaryIndexes: [
        {
          name: "userId-index",
          hashKey: "userId",
          projectionType: "ALL",
        },
      ],
    });

    const teamsTable = new aws.dynamodb.Table("teams", {
      attributes: [
        { name: "orgId", type: "S" },
        { name: "teamId", type: "S" },
      ],
      hashKey: "orgId",
      rangeKey: "teamId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const teamMembersTable = new aws.dynamodb.Table("team-members", {
      attributes: [
        { name: "teamId", type: "S" },
        { name: "userId", type: "S" },
      ],
      hashKey: "teamId",
      rangeKey: "userId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
      globalSecondaryIndexes: [
        {
          name: "userId-index",
          hashKey: "userId",
          projectionType: "ALL",
        },
      ],
    });

    const availabilityRequestsTable = new aws.dynamodb.Table(
      "availability-requests",
      {
        attributes: [
          { name: "rosterId", type: "S" },
          { name: "requestId", type: "S" },
          { name: "userId", type: "S" },
        ],
        hashKey: "rosterId",
        rangeKey: "requestId",
        billingMode: "PAY_PER_REQUEST",
        serverSideEncryption: {
          enabled: true,
          kmsKeyArn: kmsKey.arn,
        },
        globalSecondaryIndexes: [
          {
            name: "userId-index",
            hashKey: "userId",
            projectionType: "ALL",
          },
        ],
      }
    );

    const swapRequestsTable = new aws.dynamodb.Table("swap-requests", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "requestId", type: "S" },
        { name: "userId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "requestId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
      globalSecondaryIndexes: [
        {
          name: "userId-index",
          hashKey: "userId",
          projectionType: "ALL",
        },
      ],
    });

    const shiftLocksTable = new aws.dynamodb.Table("shift-locks", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "lockId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "lockId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const changeProposalsTable = new aws.dynamodb.Table("change-proposals", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "proposalId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "proposalId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const auditLogsTable = new aws.dynamodb.Table("audit-logs", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "logId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "logId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const shareCodesTable = new aws.dynamodb.Table("share-codes", {
      attributes: [{ name: "code", type: "S" }],
      hashKey: "code",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const presenceTable = new aws.dynamodb.Table("presence", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "userId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "userId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const timeClockTable = new aws.dynamodb.Table("time-clock", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "entryId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "entryId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const aiFeedbackTable = new aws.dynamodb.Table("ai-feedback", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "feedbackId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "feedbackId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
    });

    const analyticsTable = new aws.dynamodb.Table("analytics-events", {
      attributes: [
        { name: "rosterId", type: "S" },
        { name: "eventId", type: "S" },
        { name: "userId", type: "S" },
      ],
      hashKey: "rosterId",
      rangeKey: "eventId",
      billingMode: "PAY_PER_REQUEST",
      serverSideEncryption: {
        enabled: true,
        kmsKeyArn: kmsKey.arn,
      },
      globalSecondaryIndexes: [
        {
          name: "userId-index",
          hashKey: "userId",
          projectionType: "ALL",
        },
      ],
    });

    const rosterSalt = new random.RandomPassword("roster-salt", {
      length: 24,
      special: false,
    });

    const exportsBucket = new aws.s3.Bucket("roster-exports", {
      forceDestroy: true,
    });

    const oac = new aws.cloudfront.OriginAccessControl(
      "roster-exports-oac",
      {
        name: "roster-exports-oac",
        originAccessControlOriginType: "s3",
        signingBehavior: "always",
        signingProtocol: "sigv4",
      }
    );

    const exportsDistribution = new aws.cloudfront.Distribution(
      "roster-exports-cdn",
      {
        enabled: true,
        origins: [
          {
            domainName: exportsBucket.bucketRegionalDomainName,
            originId: exportsBucket.arn,
            originAccessControlId: oac.id,
          },
        ],
        defaultCacheBehavior: {
          targetOriginId: exportsBucket.arn,
          viewerProtocolPolicy: "redirect-to-https",
          allowedMethods: ["GET", "HEAD"],
          cachedMethods: ["GET", "HEAD"],
          forwardedValues: {
            queryString: true,
            cookies: { forward: "none" },
          },
        },
        restrictions: {
          geoRestriction: {
            restrictionType: "none",
          },
        },
        viewerCertificate: {
          cloudfrontDefaultCertificate: true,
        },
      }
    );

    const exportsBucketPolicy = new aws.s3.BucketPolicy(
      "roster-exports-policy",
      {
        bucket: exportsBucket.id,
        policy: pulumi
          .all([exportsBucket.arn, exportsDistribution.arn])
          .apply(([bucketArn, distArn]) =>
            JSON.stringify({
              Version: "2012-10-17",
              Statement: [
                {
                  Effect: "Allow",
                  Principal: { Service: "cloudfront.amazonaws.com" },
                  Action: "s3:GetObject",
                  Resource: `${bucketArn}/*`,
                  Condition: {
                    StringEquals: {
                      "AWS:SourceArn": distArn,
                    },
                  },
                },
              ],
            })
          ),
      }
    );

    const notificationsTopic = new aws.sns.Topic("roster-notifications");

    const lambdaRole = new aws.iam.Role("api-lambda-role", {
      assumeRolePolicy: aws.iam.assumeRolePolicyForPrincipal({
        Service: "lambda.amazonaws.com",
      }),
    });

    new aws.iam.RolePolicyAttachment("api-lambda-basic", {
      role: lambdaRole.name,
      policyArn: aws.iam.ManagedPolicies.AWSLambdaBasicExecutionRole,
    });

    new aws.iam.RolePolicy("api-lambda-policy", {
      role: lambdaRole.id,
      policy: pulumi.all([
        rostersTable.arn,
        rosterMembersTable.arn,
        rosterDataTable.arn,
        rosterUpdatesTable.arn,
        orgsTable.arn,
        orgMembersTable.arn,
        teamsTable.arn,
        teamMembersTable.arn,
        availabilityRequestsTable.arn,
        swapRequestsTable.arn,
        shiftLocksTable.arn,
        changeProposalsTable.arn,
        auditLogsTable.arn,
        shareCodesTable.arn,
        presenceTable.arn,
        timeClockTable.arn,
        aiFeedbackTable.arn,
        analyticsTable.arn,
        exportsBucket.arn,
        notificationsTopic.arn,
        userProfilesTable.arn,
        appSecrets.arn,
        userPool.arn,
        kmsKey.arn,
      ]).apply(
        ([
          rostersArn,
          membersArn,
          dataArn,
          updatesArn,
          orgsArn,
          orgMembersArn,
          teamsArn,
          teamMembersArn,
          availabilityArn,
          swapArn,
          locksArn,
          proposalsArn,
          auditArn,
          shareCodesArn,
          presenceArn,
          timeClockArn,
          aiFeedbackArn,
          analyticsArn,
          exportsArn,
          notificationsArn,
          profilesArn,
          secretsArn,
          userPoolArn,
          kmsArn,
        ]) =>
          JSON.stringify({
            Version: "2012-10-17",
            Statement: [
              {
                Effect: "Allow",
                Action: [
                  "dynamodb:GetItem",
                  "dynamodb:PutItem",
                  "dynamodb:UpdateItem",
                  "dynamodb:Query",
                  "dynamodb:Scan",
                  "dynamodb:BatchGetItem",
                ],
                Resource: [
                  rostersArn,
                  membersArn,
                  dataArn,
                  updatesArn,
                  orgsArn,
                  orgMembersArn,
                  teamsArn,
                  teamMembersArn,
                  availabilityArn,
                  swapArn,
                  locksArn,
                  proposalsArn,
                  auditArn,
                  shareCodesArn,
                  presenceArn,
                  timeClockArn,
                  aiFeedbackArn,
                  analyticsArn,
                  exportsArn,
                  `${exportsArn}/*`,
                  profilesArn,
                  `${membersArn}/index/*`,
                  `${orgMembersArn}/index/*`,
                  `${teamMembersArn}/index/*`,
                  `${availabilityArn}/index/*`,
                  `${swapArn}/index/*`,
                  `${analyticsArn}/index/*`,
                ],
              },
              {
                Effect: "Allow",
                Action: ["cognito-idp:AdminDeleteUser"],
                Resource: userPoolArn,
              },
              {
                Effect: "Allow",
                Action: ["sns:Publish"],
                Resource: notificationsArn,
              },
              {
                Effect: "Allow",
                Action: ["ses:SendEmail", "ses:SendRawEmail"],
                Resource: "*",
              },
              {
                Effect: "Allow",
                Action: ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"],
                Resource: kmsArn,
              },
              {
                Effect: "Allow",
                Action: ["secretsmanager:GetSecretValue"],
                Resource: secretsArn,
              },
              {
                Effect: "Allow",
                Action: [
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:PutObjectAcl",
                ],
                Resource: [`${exportsArn}/*`],
              },
              {
                Effect: "Allow",
                Action: ["bedrock:InvokeModel"],
                Resource: "*",
              },
            ],
          })
      ),
    });

    const handlerPath = path.resolve(process.cwd(), "backend/api/index.js");
    const apiBundlePath = path.join(apiOutDir, "index.js");
    await esbuild.build({
      entryPoints: [handlerPath],
      bundle: true,
      platform: "node",
      target: ["node18"],
      outfile: apiBundlePath,
    });

    const apiFunction = new aws.lambda.Function("roster-api", {
      runtime: "nodejs18.x",
      role: lambdaRole.arn,
      handler: "index.handler",
      code: new pulumi.asset.AssetArchive({
        "index.js": new pulumi.asset.FileAsset(apiBundlePath),
      }),
      environment: {
        variables: {
          ROSTERS_TABLE: rostersTable.name,
          ROSTER_MEMBERS_TABLE: rosterMembersTable.name,
          ROSTER_DATA_TABLE: rosterDataTable.name,
          ROSTER_UPDATES_TABLE: rosterUpdatesTable.name,
          ORGS_TABLE: orgsTable.name,
          ORG_MEMBERS_TABLE: orgMembersTable.name,
          TEAMS_TABLE: teamsTable.name,
          TEAM_MEMBERS_TABLE: teamMembersTable.name,
          AVAILABILITY_REQUESTS_TABLE: availabilityRequestsTable.name,
          SWAP_REQUESTS_TABLE: swapRequestsTable.name,
          SHIFT_LOCKS_TABLE: shiftLocksTable.name,
          CHANGE_PROPOSALS_TABLE: changeProposalsTable.name,
          AUDIT_LOGS_TABLE: auditLogsTable.name,
          SHARE_CODES_TABLE: shareCodesTable.name,
          PRESENCE_TABLE: presenceTable.name,
          TIME_CLOCK_TABLE: timeClockTable.name,
          AI_FEEDBACK_TABLE: aiFeedbackTable.name,
          ANALYTICS_TABLE: analyticsTable.name,
          EXPORTS_BUCKET: exportsBucket.bucket,
          CLOUDFRONT_URL: exportsDistribution.domainName,
          SNS_TOPIC_ARN: notificationsTopic.arn,
          SES_REGION: process.env.SES_REGION ?? region,
          APP_CONFIG_SECRET_ARN: appSecrets.arn,
          USER_PROFILES_TABLE: userProfilesTable.name,
          ROSTER_SALT: rosterSalt.result,
          USER_POOL_ID: userPool.id,
          UPDATE_BUCKET: exportsBucket.bucket,
          UPDATE_MANIFEST_KEY: process.env.UPDATE_MANIFEST_KEY ?? "updates/manifest.json",
        },
      },
    });

    const api = new aws.apigatewayv2.Api("roster-api-gateway", {
      protocolType: "HTTP",
      corsConfiguration: {
        allowHeaders: ["authorization", "content-type"],
        allowMethods: ["GET", "POST", "OPTIONS"],
        allowOrigins: ["*"],
      },
    });

    const integration = new aws.apigatewayv2.Integration(
      "roster-api-integration",
      {
        apiId: api.id,
        integrationType: "AWS_PROXY",
        integrationUri: apiFunction.arn,
        payloadFormatVersion: "2.0",
      }
    );

    const jwtAuthorizer = new aws.apigatewayv2.Authorizer(
      "roster-api-jwt-authorizer",
      {
        apiId: api.id,
        authorizerType: "JWT",
        identitySources: ["$request.header.Authorization"],
        jwtConfiguration: {
          issuer: pulumi.interpolate`https://cognito-idp.${region}.amazonaws.com/${userPool.id}`,
          audience: [userPoolClient.id],
        },
      }
    );

    const routes = [
      { key: "GET /health", auth: false },
      { key: "POST /rosters/create", auth: true },
      { key: "POST /rosters/delete", auth: true },
      { key: "POST /rosters/join", auth: true },
      { key: "GET /rosters", auth: true },
      { key: "POST /roster/save", auth: true },
      { key: "GET /roster/load", auth: true },
      { key: "POST /roster/update", auth: true },
      { key: "GET /roster/updates", auth: true },
      { key: "POST /orgs/create", auth: true },
      { key: "GET /orgs", auth: true },
      { key: "POST /orgs/members/role", auth: true },
      { key: "POST /teams/create", auth: true },
      { key: "GET /teams", auth: true },
      { key: "POST /teams/members/add", auth: true },
      { key: "POST /availability/request", auth: true },
      { key: "GET /availability/requests", auth: true },
      { key: "POST /availability/approve", auth: true },
      { key: "POST /swaps/request", auth: true },
      { key: "GET /swaps/requests", auth: true },
      { key: "POST /swaps/respond", auth: true },
      { key: "POST /locks/set", auth: true },
      { key: "GET /locks", auth: true },
      { key: "POST /locks/remove", auth: true },
      { key: "POST /proposals/create", auth: true },
      { key: "GET /proposals", auth: true },
      { key: "POST /proposals/resolve", auth: true },
      { key: "GET /audit", auth: true },
      { key: "POST /profile", auth: true },
      { key: "POST /account/delete", auth: true },
      { key: "POST /share/create", auth: true },
      { key: "POST /share/access", auth: false },
      { key: "POST /share/access-auth", auth: true },
      { key: "POST /share/leave", auth: false },
      { key: "POST /exports/roster", auth: true },
      { key: "POST /presence/heartbeat", auth: true },
      { key: "GET /presence/list", auth: true },
      { key: "POST /timeclock/import", auth: true },
      { key: "GET /timeclock", auth: true },
      { key: "POST /ai/feedback", auth: true },
      { key: "GET /roles/templates", auth: true },
      { key: "POST /ai/suggestions", auth: true },
      { key: "POST /analytics/track", auth: true },
    ];

    routes.forEach((route) => {
      new aws.apigatewayv2.Route(
        `route-${route.key.replace(/[^a-zA-Z0-9]/g, "-")}`,
        {
          apiId: api.id,
          routeKey: route.key,
          target: pulumi.interpolate`integrations/${integration.id}`,
          authorizationType: route.auth ? "JWT" : "NONE",
          authorizerId: route.auth ? jwtAuthorizer.id : undefined,
        }
      );
    });

    const schedulerLambdaRole = new aws.iam.Role("scheduler-lambda-role", {
      assumeRolePolicy: aws.iam.assumeRolePolicyForPrincipal({
        Service: "lambda.amazonaws.com",
      }),
    });

    new aws.iam.RolePolicyAttachment("scheduler-lambda-basic", {
      role: schedulerLambdaRole.name,
      policyArn: aws.iam.ManagedPolicies.AWSLambdaBasicExecutionRole,
    });

    new aws.iam.RolePolicy("scheduler-lambda-policy", {
      role: schedulerLambdaRole.id,
      policy: pulumi
        .all([
          availabilityRequestsTable.arn,
          swapRequestsTable.arn,
          changeProposalsTable.arn,
          notificationsTopic.arn,
        ])
        .apply(([availabilityArn, swapArn, proposalsArn, notificationsArn]) =>
          JSON.stringify({
            Version: "2012-10-17",
            Statement: [
              {
                Effect: "Allow",
                Action: ["dynamodb:Scan"],
                Resource: [availabilityArn, swapArn, proposalsArn],
              },
              {
                Effect: "Allow",
                Action: ["sns:Publish"],
                Resource: notificationsArn,
              },
            ],
          })
        ),
    });

    const schedulerInvokeRole = new aws.iam.Role("scheduler-invoke-role", {
      assumeRolePolicy: aws.iam.assumeRolePolicyForPrincipal({
        Service: "scheduler.amazonaws.com",
      }),
    });

    const schedulerHandlerPath = path.resolve(
      process.cwd(),
      "backend/scheduler/index.js"
    );
    const schedulerBundlePath = path.join(schedulerOutDir, "index.js");
    await esbuild.build({
      entryPoints: [schedulerHandlerPath],
      bundle: true,
      platform: "node",
      target: ["node18"],
      outfile: schedulerBundlePath,
    });
    const schedulerFunction = new aws.lambda.Function("roster-scheduler", {
      runtime: "nodejs18.x",
      role: schedulerLambdaRole.arn,
      handler: "index.handler",
      code: new pulumi.asset.AssetArchive({
        "index.js": new pulumi.asset.FileAsset(schedulerBundlePath),
      }),
      environment: {
        variables: {
          AVAILABILITY_REQUESTS_TABLE: availabilityRequestsTable.name,
          SWAP_REQUESTS_TABLE: swapRequestsTable.name,
          CHANGE_PROPOSALS_TABLE: changeProposalsTable.name,
          SNS_TOPIC_ARN: notificationsTopic.arn,
        },
      },
    });

    new aws.iam.RolePolicy("scheduler-invoke-policy", {
      role: schedulerInvokeRole.id,
      policy: schedulerFunction.arn.apply((arn) =>
        JSON.stringify({
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: ["lambda:InvokeFunction"],
              Resource: arn,
            },
          ],
        })
      ),
    });

    new aws.lambda.Permission("scheduler-invoke-permission", {
      action: "lambda:InvokeFunction",
      function: schedulerFunction.name,
      principal: "scheduler.amazonaws.com",
    });

    new aws.scheduler.Schedule("daily-approval-summary", {
      scheduleExpression: "rate(1 day)",
      flexibleTimeWindow: { mode: "OFF" },
      target: {
        arn: schedulerFunction.arn,
        roleArn: schedulerInvokeRole.arn,
      },
    });

    const stage = new aws.apigatewayv2.Stage("roster-api-stage", {
      apiId: api.id,
      name: stageName,
      autoDeploy: true,
    });

    new aws.lambda.Permission("roster-api-permission", {
      action: "lambda:InvokeFunction",
      function: apiFunction.name,
      principal: "apigateway.amazonaws.com",
      sourceArn: pulumi.interpolate`${api.executionArn}/*/*`,
    });

    new aws.iam.RolePolicy("identity-api-policy", {
      role: authenticatedRole.id,
      policy: api.executionArn.apply((arn) =>
        JSON.stringify({
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: ["execute-api:Invoke"],
              Resource: `${arn}/*/*`,
            },
          ],
        })
      ),
    });

    new aws.cognito.IdentityPoolRoleAttachment(
      "identity-pool-roles",
      {
        identityPoolId: identityPool.id,
        roles: {
          authenticated: authenticatedRole.arn,
        },
      }
    );

    return {
      apiUrl: pulumi.interpolate`${api.apiEndpoint}/${stage.name}`,
      userPoolId: userPool.id,
      userPoolClientId: userPoolClient.id,
      cognitoDomain: userPoolDomain.domain,
      cognitoCustomDomain: customDomain || null,
      cognitoDomainValidation: validationOptions ?? null,
      identityPoolId: identityPool.id,
      exportsBucket: exportsBucket.bucket,
      exportsCdn: exportsDistribution.domainName,
      notificationsTopic: notificationsTopic.arn,
      region,
      stage: stage.name,
    };
  },
});
