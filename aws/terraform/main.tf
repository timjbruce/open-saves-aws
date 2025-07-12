provider "aws" {
  region = var.region
}

module "step1_cluster_ecr" {
  source = "./modules/step1-cluster-ecr"
  
  region        = var.region
  cluster_name  = var.cluster_name
  ecr_repo_name = var.ecr_repo_name
}

module "step2_infrastructure" {
  source = "./modules/step2-infrastructure"
  
  region           = var.region
  architecture     = var.architecture
  vpc_id           = module.step1_cluster_ecr.vpc_id
  private_subnet_ids = module.step1_cluster_ecr.private_subnet_ids
  ecr_repo_uri     = module.step1_cluster_ecr.ecr_repo_uri
  config_path      = "${path.module}/config"
  environment      = var.environment
  eks_cluster_security_group_id = module.step1_cluster_ecr.cluster_security_group_id
}

module "step3_container_images" {
  source = "./modules/step3-container-images"
  
  region       = var.region
  architecture = var.architecture
  ecr_repo_uri = module.step1_cluster_ecr.ecr_repo_uri
  source_path  = "${path.module}/../"
  source_hash  = var.source_hash
  s3_bucket_name = module.step2_infrastructure.s3_bucket_name
  redis_endpoint = module.step2_infrastructure.redis_endpoint
}

module "step4_compute_app" {
  source = "./modules/step4-compute-app"
  
  region            = var.region
  architecture      = var.architecture
  cluster_name      = var.cluster_name
  namespace         = var.namespace
  eks_endpoint      = module.step1_cluster_ecr.cluster_endpoint
  eks_ca_certificate = module.step1_cluster_ecr.cluster_certificate_authority_data
  oidc_provider     = module.step1_cluster_ecr.oidc_provider
  oidc_provider_arn = module.step1_cluster_ecr.oidc_provider_arn
  private_subnet_ids = module.step1_cluster_ecr.private_subnet_ids
  ecr_repo_uri      = module.step1_cluster_ecr.ecr_repo_uri
  dynamodb_table_arns = module.step2_infrastructure.dynamodb_table_arns
  dynamodb_table_names = module.step2_infrastructure.dynamodb_table_names
  s3_bucket_arn     = module.step2_infrastructure.s3_bucket_arn
  s3_bucket_id      = module.step2_infrastructure.s3_bucket_id
  s3_bucket_name    = module.step2_infrastructure.s3_bucket_name
  redis_endpoint    = module.step2_infrastructure.redis_endpoint
  parameter_store_name = module.step2_infrastructure.parameter_store_name
}

module "step5_cloudfront_waf" {
  source = "./modules/step5-cloudfront-waf"
  
  region              = var.region
  architecture        = var.architecture
  vpc_id              = module.step1_cluster_ecr.vpc_id
  load_balancer_dns   = module.step4_compute_app.load_balancer_hostname
  service_account_role_arn = module.step4_compute_app.service_account_role_arn
  eks_cluster_security_group_id = module.step1_cluster_ecr.cluster_security_group_id
}
