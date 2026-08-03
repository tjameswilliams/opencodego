#!/bin/bash
# Build and ship the Go for OpenCode site. Infra via CDK, content via
# s3 sync, then a CloudFront invalidation. Modelled on the Tomte site's
# deploy; same AWS profile.
#
#   scripts/deploy.sh
#
# Set SITE_DOMAIN once goforopencode.com is registered and its hosted zone
# exists; until then the stack deploys on the CloudFront domain alone and
# this script still works.
set -euo pipefail

PROFILE="${AWS_PROFILE_OVERRIDE:-radius}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
DMG="${OPENCODEGO_DMG:-$REPO/dist/OpenCodeGo.dmg}"
export SITE_DOMAIN="${SITE_DOMAIN:-goforopencode.com}"

echo "==> Building site"
(cd "$ROOT" && npm run build)

echo "==> Deploying infra (profile: $PROFILE, domain: ${SITE_DOMAIN:-none})"
(cd "$ROOT/infra" && npx cdk deploy GoForOpenCodeWebsite \
  --require-approval never \
  --profile "$PROFILE" \
  --outputs-file outputs.json)

BUCKET=$(node -p "require('$ROOT/infra/outputs.json').GoForOpenCodeWebsite.SiteBucketName")
DIST_ID=$(node -p "require('$ROOT/infra/outputs.json').GoForOpenCodeWebsite.DistributionId")
URL=$(node -p "require('$ROOT/infra/outputs.json').GoForOpenCodeWebsite.SiteUrl")

echo "==> Syncing site to s3://$BUCKET"
# --exclude downloads/*: releases are uploaded below and must survive a
# --delete sync of the site content.
aws s3 sync "$ROOT/dist" "s3://$BUCKET" \
  --delete \
  --exclude "downloads/*" \
  --profile "$PROFILE" \
  --region us-east-1

if [ -f "$DMG" ]; then
  echo "==> Uploading desktop binary ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
  aws s3 cp "$DMG" "s3://$BUCKET/downloads/GoForOpenCode.dmg" \
    --content-type application/x-apple-diskimage \
    --profile "$PROFILE" \
    --region us-east-1
else
  echo "==> No dmg at $DMG — skipping binary (set OPENCODEGO_DMG to override)"
fi

# Sparkle: versioned dmgs, binary deltas, and the signed appcast. Uploaded
# without --delete so releases accumulate; installed apps poll
# downloads/appcast.xml (SUFeedURL) and fetch what it references. Deleting
# an old dmg breaks the delta chain for anyone who skipped a version.
UPDATES="$(dirname "$DMG")/updates"
if [ -f "$UPDATES/appcast.xml" ]; then
  echo "==> Uploading Sparkle updates from $UPDATES"
  aws s3 sync "$UPDATES" "s3://$BUCKET/downloads" \
    --exclude "*" --include "*.dmg" --include "*.delta" \
    --profile "$PROFILE" \
    --region us-east-1
  aws s3 cp "$UPDATES/appcast.xml" "s3://$BUCKET/downloads/appcast.xml" \
    --content-type application/xml \
    --cache-control "max-age=300" \
    --profile "$PROFILE" \
    --region us-east-1
else
  echo "==> No appcast at $UPDATES — skipping Sparkle upload"
fi

echo "==> Invalidating CloudFront cache"
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/*" \
  --profile "$PROFILE" \
  --no-cli-pager \
  --query 'Invalidation.Id' \
  --output text

echo "==> Live at $URL"
