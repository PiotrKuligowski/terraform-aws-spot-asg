resource "aws_launch_template" "this" {
  name_prefix                          = join("-", [var.project, var.component, "-"])
  image_id                             = var.ami_id
  instance_type                        = var.instance_type
  ebs_optimized                        = true
  key_name                             = var.ssh_key_name
  instance_initiated_shutdown_behavior = "terminate"
  user_data                            = base64encode(local.user_data)
  tags                                 = var.tags

  # If AMI contained more volumes, these will not be included as below is an override
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 8
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  credit_specification {
    cpu_credits = "standard"
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  network_interfaces {
    associate_public_ip_address = var.associate_public_ip_address
    delete_on_termination       = true
    security_groups             = var.create_sg ? [aws_security_group.this[0].id] : var.security_groups
  }

  instance_market_options {
    market_type = "spot"

    spot_options {
      instance_interruption_behavior = "terminate"
      spot_instance_type             = "one-time"
    }
  }
}

resource "aws_autoscaling_group" "this" {
  depends_on            = [aws_iam_instance_profile.this, aws_iam_role_policy_attachment.ec2-attach]
  name                  = join("-", [var.project, var.component, local.hash])
  max_size              = var.asg_max_size
  min_size              = var.asg_min_size
  desired_capacity      = var.asg_desired_capacity
  max_instance_lifetime = 2678400 # 3600 * 24 * 31 = 1 Month
  vpc_zone_identifier   = var.subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = join("-", [var.project, var.component])
  }

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# SECURITY --------------------------------------------------------------------

resource "aws_security_group" "this" {
  count  = var.create_sg ? 1 : 0
  name   = join("-", [var.project, var.component, local.hash])
  vpc_id = var.vpc_id
  tags   = var.tags
}

resource "aws_security_group_rule" "egress" {
  count             = var.create_sg ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.this[0].id
}

# IAM -------------------------------------------------------------------------

data "aws_iam_policy_document" "this" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = join("-", [var.project, var.component, local.hash])
  assume_role_policy = data.aws_iam_policy_document.this.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "this" {
  name = join("-", [var.project, var.component, local.hash])
  role = aws_iam_role.this.name
  tags = var.tags
}

data "aws_iam_policy_document" "ec2-document" {
  count = length(var.policy_statements) > 0 ? 1 : 0
  dynamic "statement" {
    for_each = var.policy_statements
    content {
      sid       = statement.key
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_policy" "ec2-policy" {
  count  = length(var.policy_statements) > 0 ? 1 : 0
  name   = join("-", [var.project, var.component, local.hash])
  policy = data.aws_iam_policy_document.ec2-document[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2-attach" {
  count      = length(var.policy_statements) > 0 ? 1 : 0
  policy_arn = aws_iam_policy.ec2-policy[0].arn
  role       = aws_iam_role.this.name
}

data "aws_iam_policy" "aws-managed-policy-for-ssm" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "nodes-policy-attach" {
  policy_arn = data.aws_iam_policy.aws-managed-policy-for-ssm.arn
  role       = aws_iam_role.this.name
}

resource "random_uuid" "hash" {}

# DATA ------------------------------------------------------------------------

data "aws_route53_zone" "public" {
  count = var.domain != null ? 1 : 0
  name  = var.domain
}

data "aws_route53_zone" "private" {
  count        = var.private_domain != null ? 1 : 0
  name         = var.private_domain
  private_zone = true
}

data "aws_region" "current" {}

# LOCALS ----------------------------------------------------------------------

locals {
  hash = substr(random_uuid.hash.result, 0, 8)

  opt_user_data_install_awscliv2v = var.install_awscliv2 == false ? "" : <<-EOF
DEBIAN_FRONTEND=noninteractive apt-get install -y unzip
filename="awscli-exe-linux-$(uname -i).zip"
curl -O https://awscli.amazonaws.com/$filename
unzip -q $filename
./aws/install --update
rm -rf ./aws
rm -f $filename
aws --version
EOF

  opt_user_data_update_dns_entry = var.domain == null ? "" : <<EOF
public_ip=$(curl --silent http://169.254.169.254/latest/meta-data/public-ipv4)
cat > /tmp/r53_update.json <<CONF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${var.record_name}.${data.aws_route53_zone.public[0].name}",
        "Type": "A",
        "TTL": ${var.record_ttl},
        "ResourceRecords": [{"Value":"$public_ip"}]
      }
    }
  ]
}
CONF
aws route53 change-resource-record-sets \
  --hosted-zone-id "${data.aws_route53_zone.public[0].id}" \
  --change-batch file:///tmp/r53_update.json
rm /tmp/r53_update.json
EOF

  opt_user_data_update_private_dns_entry = var.private_domain == null ? "" : <<EOF
private_ip=$(curl --silent http://169.254.169.254/latest/meta-data/local-ipv4)
cat > /tmp/r53_update.json <<CONF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${var.record_name}.${data.aws_route53_zone.private[0].name}",
        "Type": "A",
        "TTL": ${var.record_ttl},
        "ResourceRecords": [{"Value":"$private_ip"}]
      }
    }
  ]
}
CONF
aws route53 change-resource-record-sets \
  --hosted-zone-id "${data.aws_route53_zone.private[0].id}" \
  --change-batch file:///tmp/r53_update.json
rm /tmp/r53_update.json
EOF

  opt_user_data_disable_source_dest_check = var.disable_source_dest_check == false ? "" : <<EOF
local_ip=$(hostname -I | awk '{print $1}')
instance_id=$(aws ec2 describe-instances --filter Name=private-ip-address,Values="$local_ip" | jq -r '.Reservations[].Instances[] | .InstanceId')
aws ec2 modify-instance-attribute --no-source-dest-check --instance-id "$instance_id" --region ${data.aws_region.current.name}
EOF

  user_data = join("\n", [
    "#!/bin/bash -xe",
    local.opt_user_data_install_awscliv2v,
    local.opt_user_data_update_dns_entry,
    local.opt_user_data_update_private_dns_entry,
    local.opt_user_data_disable_source_dest_check,
    var.user_data
  ])
}