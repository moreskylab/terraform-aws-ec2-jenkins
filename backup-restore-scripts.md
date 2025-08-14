# Jenkins Backup and Restore Scripts

## Manual Backup
To create a manual backup:
```bash
sudo /opt/jenkins-backup/backup-jenkins.sh <backup-bucket-name>
```

## List Available Backups
To see all available backups in S3:
```bash
/opt/jenkins-backup/list-backups.sh <backup-bucket-name>
```

## Restore from Backup
To restore Jenkins from a backup:
```bash
sudo /opt/jenkins-backup/restore-jenkins.sh <backup-bucket-name> <backup-file-name>
```

Example:
```bash
sudo /opt/jenkins-backup/restore-jenkins.sh tf-jenkins-backup-12345678 jenkins-backup-20240814_120000.tar.gz
```

## Automated Backups
- Daily backup: Every day at 2:00 AM
- Weekly backup: Every Sunday at 1:00 AM
- Retention: 30 days in S3, 7 days for old versions

## What's Backed Up
- Jenkins configuration files
- Job configurations
- Plugins
- User data
- Security settings

## What's Excluded
- Workspace files (can be large and rebuilt)
- Build archives
- Log files
- Temporary files

## Logs
Check backup logs at: `/var/log/jenkins-backup.log`