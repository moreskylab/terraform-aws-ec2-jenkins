#!/bin/bash

# Variables
BACKUP_BUCKET="${backup_bucket}"
JENKINS_HOME="/var/lib/jenkins"
BACKUP_DIR="/opt/jenkins-backup"
LOG_FILE="/var/log/jenkins-backup.log"

# Install Jenkins and dependencies
sudo apt update -y
sudo apt install ansible wget unzip cron -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Jenkins using Ansible
ansible-galaxy role install moreskylab.jenkins-ssl
wget https://raw.githubusercontent.com/moreskylab/ansible-role-jenkins-ssl/refs/heads/main/test/main.yaml
ansible-playbook main.yaml -e "jenkins_domain=mynewjenkins.altgr.in"

# Wait for Jenkins to start
sleep 60

# Create backup directory
sudo mkdir -p $BACKUP_DIR
sudo chown jenkins:jenkins $BACKUP_DIR

# Create backup script
sudo tee /opt/jenkins-backup/backup-jenkins.sh > /dev/null <<'EOF'
#!/bin/bash

BACKUP_BUCKET="$1"
JENKINS_HOME="/var/lib/jenkins"
BACKUP_DIR="/opt/jenkins-backup"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="jenkins-backup-$DATE.tar.gz"
LOG_FILE="/var/log/jenkins-backup.log"

echo "$(date): Starting Jenkins backup..." >> $LOG_FILE

# Stop Jenkins service
sudo systemctl stop jenkins

# Create backup
cd $JENKINS_HOME
sudo tar -czf $BACKUP_DIR/$BACKUP_NAME \
    --exclude='workspace/*' \
    --exclude='builds/*/archive' \
    --exclude='**/*.log' \
    --exclude='**/temp*' \
    .

# Start Jenkins service
sudo systemctl start jenkins

# Upload to S3
aws s3 cp $BACKUP_DIR/$BACKUP_NAME s3://$BACKUP_BUCKET/
if [ $? -eq 0 ]; then
    echo "$(date): Backup uploaded successfully to S3" >> $LOG_FILE
    # Remove local backup after successful upload
    rm -f $BACKUP_DIR/$BACKUP_NAME
else
    echo "$(date): Failed to upload backup to S3" >> $LOG_FILE
fi

# Keep only last 3 local backups
ls -t $BACKUP_DIR/jenkins-backup-*.tar.gz | tail -n +4 | xargs -r rm --

echo "$(date): Backup process completed" >> $LOG_FILE
EOF

# Make backup script executable
sudo chmod +x /opt/jenkins-backup/backup-jenkins.sh

# Create restore script
sudo tee /opt/jenkins-backup/restore-jenkins.sh > /dev/null <<'EOF'
#!/bin/bash

BACKUP_BUCKET="$1"
BACKUP_FILE="$2"
JENKINS_HOME="/var/lib/jenkins"
BACKUP_DIR="/opt/jenkins-backup"
LOG_FILE="/var/log/jenkins-backup.log"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <backup-bucket> <backup-file-name>"
    echo "Example: $0 my-jenkins-backup jenkins-backup-20240814_120000.tar.gz"
    exit 1
fi

echo "$(date): Starting Jenkins restore from $BACKUP_FILE..." >> $LOG_FILE

# Download backup from S3
aws s3 cp s3://$BACKUP_BUCKET/$BACKUP_FILE $BACKUP_DIR/
if [ $? -ne 0 ]; then
    echo "$(date): Failed to download backup from S3" >> $LOG_FILE
    exit 1
fi

# Stop Jenkins service
sudo systemctl stop jenkins

# Backup current Jenkins home (just in case)
sudo mv $JENKINS_HOME $JENKINS_HOME.backup.$(date +%Y%m%d_%H%M%S)

# Create new Jenkins home directory
sudo mkdir -p $JENKINS_HOME

# Extract backup
cd $JENKINS_HOME
sudo tar -xzf $BACKUP_DIR/$BACKUP_FILE

# Fix permissions
sudo chown -R jenkins:jenkins $JENKINS_HOME

# Start Jenkins service
sudo systemctl start jenkins

echo "$(date): Jenkins restore completed successfully" >> $LOG_FILE
echo "Jenkins restore completed! Please check Jenkins at your domain."
EOF

# Make restore script executable
sudo chmod +x /opt/jenkins-backup/restore-jenkins.sh

# Create list backups script
sudo tee /opt/jenkins-backup/list-backups.sh > /dev/null <<'EOF'
#!/bin/bash

BACKUP_BUCKET="$1"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-bucket>"
    exit 1
fi

echo "Available Jenkins backups in S3:"
aws s3 ls s3://$BACKUP_BUCKET/ --recursive | grep jenkins-backup
EOF

# Make list script executable
sudo chmod +x /opt/jenkins-backup/list-backups.sh

# Set up daily backup cron job (runs at 2 AM daily)
echo "0 2 * * * root /opt/jenkins-backup/backup-jenkins.sh $BACKUP_BUCKET" | sudo tee -a /etc/crontab

# Set up weekly backup cron job (runs at 1 AM every Sunday)
echo "0 1 * * 0 root /opt/jenkins-backup/backup-jenkins.sh $BACKUP_BUCKET" | sudo tee -a /etc/crontab

# Restart cron service
sudo systemctl restart cron

echo "Jenkins backup and restore setup completed!"
echo "Backup bucket: $BACKUP_BUCKET"
echo "Backup scripts location: /opt/jenkins-backup/"
echo "Log file: $LOG_FILE"