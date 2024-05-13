output "cluster_endpoint" {
  value = aws_eks_cluster.example.endpoint
}

output "cluster_security_group" {
  value = aws_eks_cluster.example.vpc_config[0].cluster_security_group_id
}

output "node_group_arn" {
  value = aws_eks_node_group.example.arn
}
