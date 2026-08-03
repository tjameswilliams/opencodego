#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { WebsiteStack } from "../lib/website-stack.js";

const app = new cdk.App();

new WebsiteStack(app, "GoForOpenCodeWebsite", {
  // us-east-1: CloudFront requires its ACM certificate there. The concrete
  // account id comes from the radius profile at synth time — the
  // hosted-zone lookup needs it.
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: "us-east-1" },
  // Set once the domain is registered and its hosted zone exists. Until
  // then the stack deploys on the CloudFront domain alone.
  domainName: process.env.SITE_DOMAIN || undefined,
  description: "Go for OpenCode marketing site: S3 + CloudFront static hosting",
});
