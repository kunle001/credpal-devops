#!/usr/bin/env bash
# bootstrap.sh – One-time setup of the Terraform remote state backend.
# Run this ONCE before your first `terraform init`.
#
# Usage:
#   chmod +x terraform/scripts/bootstrap.sh
#   AWS_REGION=us-east-1 BUCKET_NAME=credpal-terraform-state ./terraform/scripts/bootstrap.sh

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
BUCKET="${BUCKET_NAME:-credpal-terraform-state}"
TABLE="credpal-terraform-locks"

echo "==> Creating S3 state bucket: $BUCKET (region: $REGION)"
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null \
    || echo "    Bucket already exists – skipping."
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null \
    || echo "    Bucket already exists – skipping."
fi

echo "==> Enabling versioning on $BUCKET"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "==> Enabling AES-256 encryption on $BUCKET"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

echo "==> Blocking all public access on $BUCKET"
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "==> Creating DynamoDB lock table: $TABLE"
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" 2>/dev/null \
  || echo "    DynamoDB table already exists – skipping."

echo "==> Creating GitHub Actions OIDC provider (account-scoped, one-time)"
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" 2>/dev/null \
  || echo "    OIDC provider already exists – skipping."

echo ""
echo "Bootstrap complete."
echo "You can now run:"
echo "  cd terraform/environments/staging && terraform init && terraform apply"
echo "  cd terraform/environments/production && terraform init && terraform apply"
