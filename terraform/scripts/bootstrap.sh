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
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
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
  --region "$REGION"

echo ""
echo "Bootstrap complete."
echo "You can now run: cd terraform/environments/staging && terraform init"
