# terraform-aws-ec2-jenkins
automate installation of jenkins with ssl

this will create ubuntu 24.04 LTS EC2 instance and install jenkins version `2.516.1` LTS.

```bash
terraform apply -auto-approve
```

> **NOTE**:- need to configure subdomain with elastic ip generated as output in your domain provider(Godaddy, Route53 etc.) for Letsencrypt SSL generation followed by nginx reverse proxy configuration.

Output:-

![jenkins_v2.516.1](images/jenkins_v2.516.1.png)
