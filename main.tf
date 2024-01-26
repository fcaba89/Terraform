######################### VPC #################################
resource "aws_vpc" "fcvpc" {
  cidr_block = var.cidrvpc
}

resource "aws_subnet" "sub1" {
    vpc_id = aws_vpc.fcvpc.id
    cidr_block = var.cidrsub1
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
}

resource "aws_subnet" "sub2" {
    vpc_id = aws_vpc.fcvpc.id
    cidr_block = var.cidrsub2
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
}

################################ Internet  Gateway #################################
resource "aws_internet_gateway" "fcigw" {
    vpc_id = aws_vpc.fcvpc.id
}

resource "aws_route_table" "fcrt" {
    vpc_id = aws_vpc.fcvpc.id

    route {
        cidr_block ="0.0.0.0/10"
        gateway_id = aws_internet_gateway.fcigw.id
    }
}

resource "aws_route_table_association" "fcrtass1" {
    subnet_id = aws_subnet.sub1.id
    route_table_id = aws_route_table.fcrt.id
}

resource "aws_route_table_association" "fcrtass2" {
    subnet_id = aws_subnet.sub2.id
    route_table_id = aws_route_table.fcrt.id
}

################################ Security Group #################################
resource "aws_security_group" "fcsg" {
    name_prefix = "fc.sg"
    description = "Allow inbound traffic"
    vpc_id = aws_vpc.fcvpc.id

    ingress {
        description = "FCSG from VPC"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "FCSG from VPC"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "fcsg"
    }
}

################################ Cloudfront #################################
resource "aws_cloudfront_origin_access_identity" "fcorigin" {
   comment = "FC CloudFront Origin Access Identity"
}

resource "aws_cloudfront_distribution" "fcdistribution" {
  origin {
    domain_name = aws_s3_bucket.fjc-bucket.bucket_regional_domain_name
     origin_id    = "S3-fjc-bucket"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.fcorigin.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "FC CloudFront Distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_cloudfront_origin_access_identity.fcorigin.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

################################ Route53 #################################
resource "aws_route53_record" "cloudfront_record" {
  zone_id = "/hostedzone/Z09707563VXB31Y2IV0LH"
  name    = "frankydesigns.net"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.fcdistribution.domain_name
    zone_id                = aws_cloudfront_distribution.fcdistribution.hosted_zone_id
    evaluate_target_health = false
  }
}


#################### S3 bucket #####################
resource "aws_s3_bucket" "fjc-bucket" {
  bucket = "fjc-bucket"

  tags = {
    Name = "fjc-bucket"
  }
}


resource "aws_s3_bucket_public_access_block" "fjc-bucket" {
  bucket = aws_s3_bucket.fjc-bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Associate CloudFront Origin Access Identity with S3 bucket
resource "aws_s3_bucket_policy" "fjc-bucket" {
  bucket = aws_s3_bucket.fjc-bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "PolicyForCloudFrontPrivateContent",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          CanonicalUser = aws_cloudfront_origin_access_identity.fcorigin.iam_arn
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.fjc-bucket.arn}/*",
      },
    ],
  })
}


resource "aws_s3_bucket_public_access_block" "fjc-buckets" {
  bucket = aws_s3_bucket.fjc-bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

################################ EC2 #################################
resource "aws_instance" "fcserver1" {
    ami = "ami-0a3c3a20c09d6f377"
    instance_type = "t2.micro"
    associate_public_ip_address = true  # Allocate a Public IPv4 address
    vpc_security_group_ids = [aws_security_group.fcsg.id]
    subnet_id = aws_subnet.sub1.id
    user_data = base64encode(file("userdata.sh"))    

    tags = {
        Name = "fcserver1"
    }
}

resource "aws_instance" "fcserver2" {
    ami = "ami-0a3c3a20c09d6f377"
    instance_type = "t2.micro"
    associate_public_ip_address = true  # Allocate a Public IPv4 address
    vpc_security_group_ids = [aws_security_group.fcsg.id]
    subnet_id = aws_subnet.sub2.id
    user_data = base64encode(file("userdata2.sh"))

    tags = {
        Name = "fcserver2"
    }
}

################################ create alb #################################
resource "aws_lb" "fclb" {
  name               = "fclb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.fcsg.id]
  subnets         = [aws_subnet.sub1.id, aws_subnet.sub2.id]
}

resource "aws_lb_target_group" "fctg" {
  name        = "fctg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.fcvpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 5
    timeout             = 2
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
}

resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.fctg.arn
  target_id        = aws_instance.fcserver1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.fctg.arn
  target_id        = aws_instance.fcserver2.id
  port             = 80
}

resource "aws_lb_listener" "fclistener" {
  load_balancer_arn = aws_lb.fclb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fctg.arn
  }
}

output "loadbalancerdns" {
  value = aws_lb.fclb.dns_name
}

################################ CloudWatch #################################
resource "aws_cloudwatch_log_group" "fc_log_group" {
  name = "fc_logs"
}

resource "aws_cloudwatch_log_stream" "fc_log_stream_instance1" {
  name           = "fcserver1"
  log_group_name = aws_cloudwatch_log_group.fc_log_group.name
}

resource "aws_cloudwatch_log_stream" "fc_log_stream_instance2" {
  name           = "fcserver2"
  log_group_name = aws_cloudwatch_log_group.fc_log_group.name
}

resource "aws_cloudwatch_log_group" "fc_log_group_alb" {
  name = "alb_log_group"
}

resource "aws_cloudwatch_log_stream" "fc_log_stream_alb" {
  name           = "alb"
  log_group_name = aws_cloudwatch_log_group.fc_log_group_alb.name
}

resource "aws_cloudwatch_log_subscription_filter" "fc_log_filter_instance1" {
  name            = "fcserver1"
  log_group_name  = aws_cloudwatch_log_group.fc_log_group.name
  filter_pattern  = "[ERROR, WARNING]"
  destination_arn = aws_cloudwatch_log_stream.fc_log_stream_instance1.arn
  role_arn = "arn:aws:iam::866934333672:user/franky"
}

resource "aws_cloudwatch_log_subscription_filter" "fc_log_filter_instance2" {
  name            = "fcserver2"
  log_group_name  = aws_cloudwatch_log_group.fc_log_group.name
  filter_pattern  = "[ERROR, WARNING]"
  destination_arn = aws_cloudwatch_log_stream.fc_log_stream_instance2.arn
  role_arn = "arn:aws:iam::866934333672:user/franky"
}

resource "aws_cloudwatch_log_subscription_filter" "fc_log_filter_alb" {
  name            = "alb"
  log_group_name  = aws_cloudwatch_log_group.fc_log_group_alb.name
  filter_pattern  = "[ERROR, WARNING]"
  destination_arn = aws_cloudwatch_log_stream.fc_log_stream_alb.arn
  role_arn = "arn:aws:iam::866934333672:user/franky"
}
