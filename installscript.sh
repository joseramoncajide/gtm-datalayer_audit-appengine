#!/bin/bash

# Instalacion del la ultima version del SDK de Google para tener acceso a las funciones beta
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update && sudo apt-get install google-cloud-sdk

# Configuracion del proyecto
PROJECT=$(gcloud config list --format 'value(core.project)')
SERVICE_ACCOUNT=$(gcloud config list --format 'value(core.account)')


INSTANCE_NAME=$(hostname)
INSTANCE_METADATA_ZONE=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor:Google")
IFS=$'/'
INSTANCE_METADATA_ZONE_SPLIT=($INSTANCE_METADATA_ZONE)
INSTANCE_ZONE="${INSTANCE_METADATA_ZONE_SPLIT[3]}"

gcloud config set account $SERVICE_ACCOUNT
gcloud config set project $PROJECT
gcloud config set compute/zone $INSTANCE_ZONE

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Google Cloud SDK instalado y configurado" --severity=INFO



# LIBRERIAS
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Instalando librerias del sistema" --severity=INFO

sudo apt-get update
#https://github.com/nodesource/distributions#deb
sudo curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -

sudo apt-get install -y nodejs
sudo apt-get install -y default-jre git
sudo apt-get install -y build-essential
sudo apt-get install -y unzip openjdk-8-jre-headless xvfb libxi6 libgconf-2-4

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Instalando Chrome" --severity=INFO
#NEW
CHROME_DRIVER_VERSION=`curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE`
#SELENIUM_STANDALONE_VERSION=3.4.0
#SELENIUM_STANDALONE_VERSION=3.5.0
#SELENIUM_SUBDIR=$(echo "$SELENIUM_STANDALONE_VERSION" | cut -d"." -f-2)
#sudo apt-get install -y unzip openjdk-8-jre-headless xvfb libxi6 libgconf-2-4
# Install Chrome.
wget -N https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -P ~/
sudo apt-get -f -y install
sudo apt-get install libgconf2-4 libxss1
#ojo a esto:
sudo apt --fix-broken install -y
sudo dpkg -i --force-depends ~/google-chrome-stable_current_amd64.deb
# Install ChromeDriver.
wget -N http://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip -P ~/
unzip ~/chromedriver_linux64.zip -d ~/
rm ~/chromedriver_linux64.zip
sudo mv -f ~/chromedriver /usr/local/bin/chromedriver
sudo chown root:root /usr/local/bin/chromedriver
sudo chmod 0755 /usr/local/bin/chromedriver
# Install Selenium.
#wget -N http://selenium-release.storage.googleapis.com/$SELENIUM_SUBDIR/selenium-server-standalone-$SELENIUM_STANDALONE_VERSION.jar -P ~/
#sudo mv -f ~/selenium-server-standalone-$SELENIUM_STANDALONE_VERSION.jar /usr/local/bin/selenium-server-standalone.jar
#sudo chown root:root /usr/local/bin/selenium-server-standalone.jar
#sudo chmod 0755 /usr/local/bin/selenium-server-standalone.jar


gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Actualizando el codigo de la app desde el repositorio https://console.cloud.google.com/code/develop/browse/gtm-datalayer-app/master" --severity=INFO
sudo -u analytics mkdir /home/analytics/app
cd /home/analytics/app

# CLONADO DESDE GCP
#OJO. DAR SCOPES AL CREAR LA MAQUINA
REPOSITORY_NAME=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/source_repo" -H "Metadata-Flavor:Google")
sudo -u analytics gcloud source repos clone $REPOSITORY_NAME

# CLONADO DESDE GitHub
#sudo -u analytics git clone https://joseramoncajide@github.com/elartedemedir/gtm-datalayer-app.git

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Instalando app" --severity=INFO

cd gtm-datalayer-app/
#Instala los paquetes en package.json
sudo -u analytics npm install
#sudo -u analytics npm install webdriverio
sudo -u analytics npm install webdriverio --save-dev
sudo -u analytics npm install --save sendgrid
sudo -u analytics npm install wdio-allure-reporter --save-dev
sudo -u analytics npm install wdio-spec-reporter --save-dev


# FOP
sudo -u analytics wget ftp://apache.cs.utah.edu/apache.org/xmlgraphics/fop/binaries/fop-2.2-bin.tar.gz
sudo -u analytics tar -zxvf fop-2.2-bin.tar.gz fop-2.2/fop --strip 1
sudo chmod 0755 fop/fop
rm fop-2.2-bin.tar.gz
sudo -u analytics mkdir fop/audit-results
sudo -u analytics mkdir fop/allure-results





#npm run audit -- --spec ./audits/conforama-PT/audit.js


#Comproba que no da error al mover o borrar
#mv package-lock.json package-lock.json.bck

#npm run allPT
### FIN

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Corrigiendo problemas de instalacion" --severity=INFO
sudo apt --fix-broken install -y


gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Ejecutando el comando $STARTUP_COMMAND" --severity=INFO

INSTANCE_METADATA_CUSTOMER=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/eam_customer" -H "Metadata-Flavor:Google")
STARTUP_COMMAND=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/audit_command" -H "Metadata-Flavor:Google")
BUCKET_NAME=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/bucket" -H "Metadata-Flavor:Google")
CURRENT_DATE=$(date +"%Y%m%d%H%M%S")
REPORT_FILE="$CURRENT_DATE-$INSTANCE_METADATA_CUSTOMER-tag_audit_report.pdf"

cd /home/analytics/app/gtm-datalayer-app

#sudo -u analytics $STARTUP_COMMAND
sudo -u analytics npm run allPT

gsutil cp ./fop/audit-results/auditoria.pdf gs://$BUCKET_NAME/$REPORT_FILE
gsutil acl ch -u AllUsers:R gs://$BUCKET_NAME/$REPORT_FILE

#sudo apt-get install python-pip python-dev build-essential -y
#sudo pip install --upgrade pip
#sudo pip install pyopenssl
#gsutil signurl -d 10m gs://eam-gtm-datalayer/$REPORT_FILE

#gsutil signurl -p notasecret -m PUT -d 1d myserviceaccount.p12 gs://mybucket/testfile


gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Resultado de la auditoria disponible en https://storage.cloud.google.com/$BUCKET_NAME/$REPORT_FILE" --severity=INFO
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: URL de descarga: https://$BUCKET_NAME.storage.googleapis.com/$REPORT_FILE" --severity=INFO

# NOTIFICATION EMAIL
#npm i yargs --save

sudo -u analytics node send_mail.js --report_url="https://storage.googleapis.com/$BUCKET_NAME/$REPORT_FILE"
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Informe enviado por email" --severity=INFO
# DELETE INSTANCE
#DEBUG
#gcloud compute instances delete gtm-datalayer-testing --zone europe-west1-b --quiet
#OK gcloud compute instances delete $INSTANCE_NAME --zone=$INSTANCE_ZONE --quiet

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Deteniendo la instancia" --severity=INFO
# sudo shutdown -h now
