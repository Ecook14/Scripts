# PowerShell script to organize the scripts repo

Write-Host "Organizing Scripts..."

# Security
Move-Item -Path "centos_hardening.sh" -Destination "security" -ErrorAction SilentlyContinue
Move-Item -Path "abuse.sh" -Destination "security" -ErrorAction SilentlyContinue
Move-Item -Path "findemailspam.sh" -Destination "security" -ErrorAction SilentlyContinue
Move-Item -Path "icmaldet.sh" -Destination "security" -ErrorAction SilentlyContinue

# Monitoring
Move-Item -Path "adlog.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "adlog(1).sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "adlog1.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "l2.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "plesk_health.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "CPUload.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "diskusage.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "ec.pl" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "logs.sh" -Destination "monitoring" -ErrorAction SilentlyContinue
Move-Item -Path "apachelogs.sh" -Destination "monitoring" -ErrorAction SilentlyContinue

# Automation
Move-Item -Path "optimize.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "maxworker.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "zabixconfig.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "wordpressfiles.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "swiss.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "swiss1.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "porta.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "porta (1).sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "permfix.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "permfix1.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "mailish.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "mailish1.sh" -Destination "automation" -ErrorAction SilentlyContinue
Move-Item -Path "mailish2.sh" -Destination "automation" -ErrorAction SilentlyContinue

Write-Host "Done! Files moved."
