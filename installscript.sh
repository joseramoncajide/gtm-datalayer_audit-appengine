#!/bin/bash

# Create an environment variable for the correct distribution
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"

# Add the Cloud SDK distribution URI as a package source
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Import the Google Cloud Platform public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# Update the package list and install the Cloud SDK
sudo apt-get update && sudo apt-get install google-cloud-sdk

# Get default project id
PROJECT=$(gcloud config list --format 'value(core.project)')

# Get default service account
SERVICE_ACCOUNT=$(gcloud config list --format 'value(core.account)')

# Get instance name
INSTANCE_NAME=$(hostname)

# Get instance zone
INSTANCE_METADATA_ZONE=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor:Google")
IFS=$'/'
INSTANCE_METADATA_ZONE_SPLIT=($INSTANCE_METADATA_ZONE)
INSTANCE_ZONE="${INSTANCE_METADATA_ZONE_SPLIT[3]}"

# Set project properties
gcloud config set account $SERVICE_ACCOUNT
gcloud config set project $PROJECT
gcloud config set compute/zone $INSTANCE_ZONE

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Google Cloud SDK instalado y configurado" --severity=INFO

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Instalando librerias del sistema" --severity=INFO

# Update os packages
sudo apt-get update
#https://github.com/nodesource/distributions#deb
sudo curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -

# Install nodejs
sudo apt-get install -y nodejs

# Install java and git
sudo apt-get install -y default-jre git

# Install packages needed to compile a debian package
sudo apt-get install -y build-essential

# Install packages needed by the app
sudo apt-get install -y unzip openjdk-8-jre-headless xvfb libxi6 libgconf-2-4

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Instalando Chrome" --severity=INFO

# Install Chrome
wget -N https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -P ~/
sudo apt-get -f -y install
sudo apt-get install libgconf2-4 libxss1
sudo apt --fix-broken install -y
sudo dpkg -i --force-depends ~/google-chrome-stable_current_amd64.deb

# Install ChromeDriver.
CHROME_DRIVER_VERSION=`curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE`
wget -N http://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip -P ~/
unzip ~/chromedriver_linux64.zip -d ~/
rm ~/chromedriver_linux64.zip
sudo mv -f ~/chromedriver /usr/local/bin/chromedriver
sudo chown root:root /usr/local/bin/chromedriver
sudo chmod 0755 /usr/local/bin/chromedriver

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Actualizando el codigo de la app desde el repositorio https://console.cloud.google.com/code/develop/browse/gtm-datalayer-app/master" --severity=INFO

# Set up app
sudo -u analytics mkdir /home/analytics/app
cd /home/analytics/app

# Clonning lastest app version from a google cloud source repository linked to GitHub
REPOSITORY_NAME=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/source_repo" -H "Metadata-Flavor:Google")
sudo -u analytics gcloud source repos clone $REPOSITORY_NAME

# Clonning lastest app version from GitHub (needs auth)
# sudo -u analytics git clone https://joseramoncajide@github.com/elartedemedir/gtm-datalayer-app.git

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Instalando app" --severity=INFO

# Deploying app
cd gtm-datalayer-app/
sudo -u analytics npm install
sudo -u analytics npm install webdriverio
sudo -u analytics npm install sendgrid
sudo -u analytics npm install wdio-allure-reporter
sudo -u analytics npm install wdio-spec-reporter

# Installing Apache FOP
sudo -u analytics wget ftp://apache.cs.utah.edu/apache.org/xmlgraphics/fop/binaries/fop-2.2-bin.tar.gz
sudo -u analytics tar -zxvf fop-2.2-bin.tar.gz fop-2.2/fop --strip 1
sudo chmod 0755 fop/fop
rm fop-2.2-bin.tar.gz
sudo -u analytics mkdir fop/audit-results
sudo -u analytics mkdir fop/allure-results

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Corrigiendo problemas de instalacion" --severity=INFO

# Fix broken install
sudo apt --fix-broken install -y

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Ejecutando el comando $STARTUP_COMMAND" --severity=INFO

# Read instance metadata
INSTANCE_METADATA_CUSTOMER=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/customer_name" -H "Metadata-Flavor:Google")
STARTUP_COMMAND=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/audit_command" -H "Metadata-Flavor:Google")
BUCKET_NAME=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/bucket" -H "Metadata-Flavor:Google")
CURRENT_DATE=$(date +"%Y%m%d%H%M%S")
REPORT_FILE="$CURRENT_DATE-$INSTANCE_METADATA_CUSTOMER-tag_audit_report.pdf"

cd /home/analytics/app/gtm-datalayer-app

echo "Comando de incio: $STARTUP_COMMAND"
sudo -u analytics npm run $STARTUP_COMMAND
# sudo -u analytics npm run allPT

# Move report to Google Cloud Storage and publish
gsutil cp ./fop/audit-results/auditoria.pdf gs://$BUCKET_NAME/$REPORT_FILE
gsutil acl ch -u AllUsers:R gs://$BUCKET_NAME/$REPORT_FILE

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Resultado de la auditoria disponible en https://storage.cloud.google.com/$BUCKET_NAME/$REPORT_FILE" --severity=INFO
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: URL de descarga: https://$BUCKET_NAME.storage.googleapis.com/$REPORT_FILE" --severity=INFO

# Send mail notificaction (sendgrid)
# npm i yargs --save
sudo -u analytics node send_mail.js --report_url="https://storage.googleapis.com/$BUCKET_NAME/$REPORT_FILE"

# Log step
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Informe enviado por email" --severity=INFO

# Stop the instance
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Deteniendo la instancia" --severity=INFO
# sudo shutdown -h now

# Delete de instance
# gcloud compute instances delete $INSTANCE_NAME --zone=$INSTANCE_ZONE --quiet
