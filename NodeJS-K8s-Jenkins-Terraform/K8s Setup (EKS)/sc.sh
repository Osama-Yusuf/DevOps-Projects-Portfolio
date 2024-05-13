#!/bin/bash

# this script create storage class for the eks cluster

# enable debug mode
set -x

# stop script on command failure
set -e

# install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin

export EKS_CLUSTER="example-eks-cluster"
export AWS_REGION="us-west-2"
export namespace=kube-system
export service_account=ebs-csi-controller-sa
export account_id=$(aws sts get-caller-identity --query "Account" --output text)
export role_name=AmazonEKS_EBS_CSI_DriverRole

# for debugging
# oidc_id=$(aws eks describe-cluster --name $EKS_CLUSTER --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5) && aws iam list-open-id-connect-providers | grep $oidc_id

# associate IAM OIDC provider with cluster
eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER --approve

oidc_provider=$(aws eks describe-cluster --name $EKS_CLUSTER --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

# create service account
cat >my-service-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $service_account
  namespace: $namespace
EOF
kubectl apply -f my-service-account.yaml

# check if the role exists
if aws iam get-role --role-name $role_name &>/dev/null; then
  # If the role exists, delete it
  aws iam detach-role-policy --role-name $role_name --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  aws iam delete-role --role-name $role_name
  echo "Recreating $role_name role"
else
  echo "$role_name does not exist. Creating..."
fi

# create IAM role and attach policy for service account
cat >aws-ebs-csi-driver-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$account_id:oidc-provider/$oidc_provider"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "$oidc_provider:aud": "sts.amazonaws.com",
          "$oidc_provider:sub": "system:serviceaccount:$namespace:$service_account"
        }
      }
    }
  ]
}
EOF

# create role
aws iam create-role --role-name $role_name --assume-role-policy-document file://aws-ebs-csi-driver-trust-policy.json --description "my-role-description"

# attach policy to role
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --role-name $role_name

# annotate service account with IAM role
kubectl annotate serviceaccount -n $namespace $service_account eks.amazonaws.com/role-arn=arn:aws:iam::$account_id:role/$role_name

# create EBS CSI driver
eksctl create addon --name aws-ebs-csi-driver --cluster $EKS_CLUSTER --service-account-role-arn arn:aws:iam::$account_id:role/$role_name --force

# create storage class
cat >sc.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aws-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
parameters:
  fsType: ext4
  type: gp2
provisioner: kubernetes.io/aws-ebs
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
kubectl apply -f sc.yaml

# delete old storage class
kubectl delete sc gp2

rm -f my-service-account.yaml aws-ebs-csi-driver-trust-policy.json sc.yaml