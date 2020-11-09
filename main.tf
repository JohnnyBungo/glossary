################################################-S3-##############################################################

module "s3_glossary" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = var.bucket 
  acl    = "private"

}

module "s3_bucket_pandas_layer" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "lambda-pandas-layer" 
  acl    = "private"

}

################################################-Lambda-##############################################################

module "lambda_translation" { 
  source = "terraform-aws-modules/lambda/aws"
  create_role = true
  function_name = "customize_translate"
  description   = "Is called when glossary is updated. Updates customized terminology on translate"
  handler       = "customize_translate.lambda_handler"
  runtime       = "python3.8"
  role_name   = "customize_translate"
  timeout       = 10
  publish = true

  source_path = "files/translation"

  environment_variables = {
    Bucket = module.s3_glossary.this_s3_bucket_id 
  }

}

module "lambda_glossary" {
  source = "terraform-aws-modules/lambda/aws"
  create_role = true
  function_name = "glossary"
  description   = "Glossary lookup service"
  handler       = "glossary.lambda_handler"
  runtime       = "python3.7" #Pandas Layer only works for 3.7
  role_name      = "glossary"
  timeout       = 10
  publish = true

  source_path = "files/glossary"

  layers = [
    module.lambda_layer_s3.this_lambda_layer_arn,
  ]

  environment_variables = {
    Bucket = module.s3_glossary.this_s3_bucket_id 
  }

}

module "lambda_layer_s3" {
  source = "terraform-aws-modules/lambda/aws"

  create_layer = true

  layer_name          = "lambda-pandas-layer-s3"
  description         = "Pandas lambda layer (deployed from S3)"
  compatible_runtimes = ["python3.7"]

  source_path = "files/layer"

  store_on_s3 = true
  s3_bucket   = module.s3_bucket_pandas_layer.this_s3_bucket_id
}

################################################-Lambda-Permissions-##############################################################

resource "aws_iam_role_policy_attachment" "glossary_s3_policy" {
  role       = module.lambda_glossary.lambda_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "translation_s3_policy" {
  role       = module.lambda_translation.lambda_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "translation_translate_policy" {
  role       = module.lambda_translation.lambda_role_name
  policy_arn = "arn:aws:iam::aws:policy/TranslateFullAccess"
}

################################################-S3-Trigger-##############################################################

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_translation.this_lambda_function_arn
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_glossary.this_s3_bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  depends_on = [module.s3_glossary.this_s3_bucket_id, module.lambda_translation.this_lambda_function_arn]
  bucket = module.s3_glossary.this_s3_bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_translation.this_lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }
}

resource "aws_s3_bucket_object" "object" {
  depends_on = [aws_s3_bucket_notification.bucket_notification,]
  bucket  = module.s3_glossary.this_s3_bucket_id
  key     = "de_en.csv"
  source  = "files/de_en.csv"

  etag    = filemd5("files/de_en.csv")
}

################################################-API-Gateway-##############################################################

resource "aws_api_gateway_rest_api" "glossary" { 
  name        = "Glossary"
  description = "API to call glossary"
}

resource "aws_api_gateway_resource" "glossary_list" {
  rest_api_id = aws_api_gateway_rest_api.glossary.id
  parent_id   = aws_api_gateway_rest_api.glossary.root_resource_id
  path_part   = "list"
}

resource "aws_api_gateway_resource" "glossary_select" {
  rest_api_id = aws_api_gateway_rest_api.glossary.id
  parent_id   = aws_api_gateway_rest_api.glossary.root_resource_id
  path_part   = "select"
}

resource "aws_api_gateway_method" "list_get" {
  rest_api_id   = aws_api_gateway_rest_api.glossary.id
  resource_id   = aws_api_gateway_resource.glossary_list.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.querystring.all_windows" = false,
    "method.request.querystring.target_lang" = true,
    "method.request.querystring.source_lang" = true,
    "method.request.querystring.start" = false,
    "method.request.querystring.s3_bucket" = false,
    "method.request.querystring.window_size" = false
  }
}

resource "aws_api_gateway_method" "select_get" {
  rest_api_id   = aws_api_gateway_rest_api.glossary.id
  resource_id   = aws_api_gateway_resource.glossary_select.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.querystring.term" = true,
    "method.request.querystring.target_lang" = true,
    "method.request.querystring.source_lang" = true
  }
}

resource "aws_api_gateway_integration" "integration_select" {
  rest_api_id             = aws_api_gateway_rest_api.glossary.id
  resource_id             = aws_api_gateway_resource.glossary_select.id
  http_method             = aws_api_gateway_method.select_get.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = module.lambda_glossary.this_lambda_function_invoke_arn
}

resource "aws_api_gateway_integration" "integration_list" {
  rest_api_id             = aws_api_gateway_rest_api.glossary.id
  resource_id             = aws_api_gateway_resource.glossary_list.id
  http_method             = aws_api_gateway_method.list_get.http_method
  integration_http_method = "GET"
  type                    = "AWS_PROXY"
  uri                     = module.lambda_glossary.this_lambda_function_invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda_select" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_glossary.this_lambda_function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.aws_region}:${var.accountId}:${aws_api_gateway_rest_api.glossary.id}/*/${aws_api_gateway_method.select_get.http_method}${aws_api_gateway_resource.glossary_select.path}"
}

resource "aws_lambda_permission" "apigw_lambda_list" {
  statement_id  = "AllowExecutionFromAPIGateway2"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_glossary.this_lambda_function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.aws_region}:${var.accountId}:${aws_api_gateway_rest_api.glossary.id}/*/${aws_api_gateway_method.list_get.http_method}${aws_api_gateway_resource.glossary_list.path}"
}