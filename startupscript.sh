#!/bin/bash



INSTANCE_NAME=$(hostname)
INSTANCE_METADATA_ZONE=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor:Google")
IFS=$'/'
INSTANCE_METADATA_ZONE_SPLIT=($INSTANCE_METADATA_ZONE)
INSTANCE_ZONE="${INSTANCE_METADATA_ZONE_SPLIT[3]}"


gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Ejecutando script de inicio" --severity=INFO

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Actualizando el codigo de la app desde el repositorio https://console.cloud.google.com/code/develop/browse/gtm-datalayer-app/master" --severity=INFO
cd /home/analytics/app
rm -Rf /home/analytics/app/tmp_gtm-datalayer-app
mkdir -p /home/analytics/app/tmp_gtm-datalayer-app
sudo -u analytics gcloud source repos clone gtm-datalayer-app /home/analytics/app/tmp_gtm-datalayer-app
rsync -rtv /home/analytics/app/tmp_gtm-datalayer-app/ /home/analytics/app/gtm-datalayer-app/
rm -Rf /home/analytics/app/tmp_gtm-datalayer-app
# CLONADO DESDE GitHub
#sudo -u analytics git clone https://joseramoncajide@github.com/elartedemedir/gtm-datalayer-app.git

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Ejecutando el comando $STARTUP_COMMAND" --severity=INFO

cd gtm-datalayer-app/

INSTANCE_METADATA_CUSTOMER=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/eam_customer" -H "Metadata-Flavor:Google")
STARTUP_COMMAND=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/audit_command" -H "Metadata-Flavor:Google")
CURRENT_DATE=$(date +"%Y%m%d%H%M%S")
REPORT_FILE="$CURRENT_DATE-$INSTANCE_METADATA_CUSTOMER-tag_audit_report.pdf"

cd /home/analytics/app/gtm-datalayer-app

sudo -u analytics $STARTUP_COMMAND
#sudo -u analytics npm run allPT

gsutil cp ./fop/audit-results/auditoria.pdf gs://eam-gtm-datalayer/$REPORT_FILE
gsutil acl ch -u AllUsers:R gs://eam-gtm-datalayer/$REPORT_FILE

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Resultado de la auditoria disponible en https://storage.cloud.google.com/eam-gtm-datalayer/$REPORT_FILE" --severity=INFO

# NOTIFICATION EMAIL
sudo -u analytics node send_mail.js --report_url="https://storage.cloud.google.com/eam-gtm-datalayer/$REPORT_FILE"
gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Informe enviado por email" --severity=INFO

# DELETE INSTANCE
#DEBUG
#gcloud compute instances delete gtm-datalayer-testing --zone europe-west1-b --quiet
#OK gcloud compute instances delete $INSTANCE_NAME --zone=$INSTANCE_ZONE --quiet

gcloud beta logging write gtm-datalayer-app "$INSTANCE_NAME: Deteniendo la instancia" --severity=INFO
sudo shutdown -h now
