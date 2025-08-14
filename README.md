# terraform-aws-ec2-jenkins
automate installation of jenkins with ssl

this will create ubuntu 24.04 LTS EC2 instance and install jenkins version `2.516.1` LTS.

```bash
terraform apply -auto-approve
```

```bash
terraform state rm aws_eip_association.web
terraform state rm aws_eip.web[0]
terraform destroy -auto-approve
```

Edit `jenkins-setup.sh` to add your domain

Example:-
```bash
# Install Jenkins using Ansible
ansible-galaxy role install moreskylab.jenkins-ssl
wget https://raw.githubusercontent.com/moreskylab/ansible-role-jenkins-ssl/refs/heads/main/test/main.yaml
ansible-playbook main.yaml -e "jenkins_domain=<YOUR_DOMAIN_NAME>"
```

> **NOTE**:- need to configure subdomain with elastic ip generated as output in your domain provider(Godaddy, Route53 etc.) for Letsencrypt SSL generation followed by nginx reverse proxy configuration.

Configure Domain

![alt text](images/godaddy_a_record_configuration.png)

Output:-

![jenkins_v2.516.1](images/jenkins_v2.516.1.png)


## Architecture Diagram

![jenkins_architecture](images/architecture_diagram.png)
