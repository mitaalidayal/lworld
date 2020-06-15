provider "aws" {
  region     = "ap-south-1"
  profile    = "mitaalid"
}



resource "tls_private_key" "privkey" {
   algorithm = "RSA"
   rsa_bits = "4096"
}



resource "aws_key_pair" "OSkey" {
  key_name   = "OSkey"
  public_key = tls_private_key.privkey.public_key_openssh
}



resource "aws_security_group" "newsecgrp" {
  name        = "OSsecuritygroup"
  vpc_id      = "vpc-59f1ec31"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

   tags = {
    Name = "OSsecuritygroup"
  }
}  



resource "aws_instance" "myin" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.OSkey.key_name  
  security_groups = [ "OSsecuritygroup" ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.privkey.private_key_pem
    host = aws_instance.myin.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
}

  tags = {
    Name = "MyFirstOS"
   }
}



output "outip" {
   value = aws_instance.myin.public_ip
   }



resource "null_resource" "local1" {
 
  provisioner "local-exec" {
    command = "echo ${aws_instance.myin.public_ip} > publicip.txt"
  }
}


resource "null_resource" "local2" {
  depends_on = [
    aws_cloudfront_distribution.s3_distribution
  ]

  provisioner "local-exec" {
    command = "chrome ${aws_instance.myin.public_ip}/gitfile.html"
  }
}




output "outaz"{
  value=aws_instance.myin.availability_zone
}



resource "aws_ebs_volume" "ebs_vol" {
  availability_zone = aws_instance.myin.availability_zone
  size              = 1

  tags = {
    Name = "MyVol"
  }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_vol.id
  instance_id = aws_instance.myin.id
  force_detach = true
}



resource "null_resource" "remote1" {
  depends_on = [
    aws_volume_attachment.ebs_att,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.privkey.private_key_pem
    host     = aws_instance.myin.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/mitaalidayal/lworld.git /var/www/html/",
    ]
  }
}



resource "aws_s3_bucket" "mitdaybuck" {
  bucket = "mitdaybuck"
  acl = "private"

  
  tags = {
    Name        = "mitdaybuck"
    Environment = "Dev"
  }
}



output "myost" {
  value = aws_s3_bucket.mitdaybuck
}



resource "aws_s3_bucket_object" "bucket_obj" {
  bucket = "mitdaybuck"
  key    = "awsimage.jpg"
  source = "awsimage.jpg"
  acl = "public-read-write"
 
}

locals {
  s3_origin_id = "s3Origin"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }
enabled             = true
origin {
        domain_name = aws_s3_bucket.bucket_obj.bucket_domain_name
        origin_id   = local.s3_origin_id
    }
restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }



viewer_certificate {
    cloudfront_default_certificate = true
  }
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.privkey.private_key_pem
    host     = aws_instance.myin.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.bucket_obj.key}' height='200px' width='200px'>\" >> /var/www/html/gitfile.html",
      "EOF",
    ]
   }
}


