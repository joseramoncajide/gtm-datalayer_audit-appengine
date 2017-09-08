#!/usr/bin/env python
#
# Copyright 2012 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import datetime
import json
import logging
import os
from pprint import pformat
import jinja2
import webapp2
import time
from google.appengine.api import app_identity
from google.appengine.ext import vendor

vendor.add('lib')

from googleapiclient import discovery
from oauth2client.client import GoogleCredentials
from google.cloud import storage
from flask import Flask
app = Flask(__name__)

compute = discovery.build('compute', 'v1', credentials=GoogleCredentials.get_application_default())


def create_bucket(bucket_name):
    """Creates a new bucket."""
    storage_client = storage.Client()
    bucket = storage_client.create_bucket(bucket_name)
    print('Bucket {} created'.format(bucket.name))


CONFIG = {
    # In DRY_RUN mode, deletes are only logged. Set this to False after you've
    # double-checked the status page and you're ready to enable the deletes.
    'DRY_RUN': False,

    # Be careful, this application could delete all instances in this project.
    # Your project id can be found on the overview tab of the Google APIs
    # Console: https://code.google.com/apis/console/
    'GCE_PROJECT_ID': app_identity.get_application_id(),

    # Instances created with these tags will never be deleted.
    'SAFE_TAGS': ['production', 'safetag'],

    # Instances are deleted after they have been running for TIMEOUT minutes.
    'TIMEOUT': 60 * 8,  # in minutes, defaulting to 8 hours

    'GC_PROJECT': 'gtm-datalayer-audit',
    'GC_ZONE': 'europe-west1-b',
    'GC_NAME': 'gtm-datalayer-audit',
    'CUSTOMER_NAME': 'conforama',
    'AUDIT_COMMAND': 'allPT',
    'CLOUD_STORAGE_BUCKET': 'gtm-datalayer-app-conforama',
    'APP_REPOSITORY_NAME': 'gtm-datalayer-app'

}
CONFIG['SAFE_TAGS'] = [t.lower() for t in CONFIG['SAFE_TAGS']]

# Obtain App Engine AppAssertion credentials and authorize HTTP connection.
# https://developers.google.com/appengine/docs/python/appidentity/overview

# Build object for the 'v1' version of the GCE API.
# https://developers.google.com/compute/docs/reference/v1beta13/
jinja_environment = jinja2.Environment(
    loader=jinja2.FileSystemLoader('templates'))


# [START list_instances]
def list_instances(compute, project, zone):
    result = compute.instances().list(project=project, zone=zone).execute()
    return result['items']
# [END list_instances]


# [START create_instance]
@app.route('/vm/create')
def create_vm():
    # Get the latest Debian Jessie image.
    image_response = compute.images().getFromFamily(
        project='ubuntu-os-cloud', family='ubuntu-1604-lts').execute()
    source_disk_image = image_response['selfLink']

    # Configure the machine
    machine_type = "zones/%s/machineTypes/n1-standard-4" % CONFIG['GC_ZONE']
    startup_script = open(
        os.path.join(
            os.path.dirname(__file__), 'installscript.sh'), 'r').read()

    config = {
        'name': CONFIG['GC_NAME'],
        'machineType': machine_type,

        # Specify the boot disk and the image to use as a source.
        'disks': [
            {
                'boot': True,
                'autoDelete': True,
                'initializeParams': {
                    'sourceImage': source_disk_image,
                }
            }
        ],

        # Specify a network interface with NAT to access the public
        # internet.
        'networkInterfaces': [{
            'network': 'global/networks/default',
            'accessConfigs': [
                {'type': 'ONE_TO_ONE_NAT', 'name': 'External NAT'}
            ]
        }],

        # Allow the instance to access cloud storage, logging and source repos.
        'serviceAccounts': [{
            'email': 'default',
            'scopes': [
                'https://www.googleapis.com/auth/devstorage.read_write',
                'https://www.googleapis.com/auth/logging.write',
                'https://www.googleapis.com/auth/devstorage.full_control',
                'https://www.googleapis.com/auth/compute',
                'https://www.googleapis.com/auth/cloud-platform',
                'https://www.googleapis.com/auth/source.full_control'
            ]
        }],

        # Metadata is readable from the instance and allows you to
        # pass configuration from deployment scripts to instances.
        'metadata': {
            'items': [{
                # Startup script is automatically executed by the
                # instance upon startup.
                'key': 'startup-script',
                'value': startup_script
            }, {
                'key': 'audit_command',
                'value': CONFIG['AUDIT_COMMAND']
            }, {
                'key': 'customer_name',
                'value': CONFIG['CUSTOMER_NAME']
            }, {
                'key': 'bucket',
                'value': CONFIG['CLOUD_STORAGE_BUCKET']
            }, {
                'key': 'source_repo',
                'value': CONFIG['APP_REPOSITORY_NAME']
            }]
        }
    }

    create_bucket(CONFIG['CLOUD_STORAGE_BUCKET'])

    result = compute.instances().insert(
        project=CONFIG['GC_PROJECT'],
        zone=CONFIG['GC_ZONE'],
        body=config).execute()
    logging.debug(result)
    return json.dumps(result, indent=4)
# [END create_instance]


# operation = create_instance(compute, project, zone, instance_name, bucket)
# wait_for_operation(compute, project, zone, operation['name'])


# [START wait_for_operation]
def wait_for_operation(compute, project, zone, operation):
    print('Waiting for operation to finish...')
    while True:
        result = compute.zoneOperations().get(
            project=project,
            zone=zone,
            operation=operation).execute()

        if result['status'] == 'DONE':
            print("done.")
            if 'error' in result:
                raise Exception(result['error'])
            return result

        time.sleep(1)
# [END wait_for_operation]


@app.route('/vm/start')
def start_vm():
    # credentials = AppAssertionCredentials(scope='https://www.googleapis.com/auth/compute')
    # http = credentials.authorize(httplib2.Http(memcache))
    # compute = discovery.build('compute', 'v1', http=http)

    # compute = discovery.build('compute','v1', credentials=GoogleCredentials.get_application_default())

    # Start the VM!
    result = compute.instances().start(instance='instance-1', zone='europe-west1-b', project='gtm-datalayer-audit').execute()
    logging.debug(result)
    return json.dumps(result, indent=4)


@app.route('/vm/stop')
def stop_vm():
    # credentials = AppAssertionCredentials(scope='https://www.googleapis.com/auth/compute')
    # http = credentials.authorize(httplib2.Http(memcache))
    # compute = discovery.build('compute', 'v1', http=http)

    # compute = discovery.build('compute','v1', credentials=GoogleCredentials.get_application_default())

    # Start the VM!
    result = compute.instances().stop(instance='instance-1', zone='europe-west1-b', project='gtm-datalayer-audit').execute()
    logging.debug(result)
    return json.dumps(result, indent=4)


@app.errorhandler(404)
def page_not_found(e):
    """Return a custom 404 error."""
    return 'Sorry, Nothing at this URL.', 404


@app.errorhandler(500)
def application_error(e):
    """Return a custom 500 error."""
    return 'Sorry, unexpected error: {}'.format(e), 500


if __name__ == '__main__':
    app.run(debug=True)

# SAMPLE_NAME = 'Instance timeout helper'
# def start_instance():
#     """logs all expired instances, calls delete API when not DRY_RUN"""
#     instances = list_instances()
#
#     for instance in instances:
#         name = instance['name']
#         zone = instance['zone'].split('/')[-1]
#         if CONFIG['DRY_RUN']:
#             logging.info("DRY_RUN, not deleted: %s", name)
#         else:
#             logging.info("START: %s", name)
#             request = compute.instances().start(
#                                     project=CONFIG['GCE_PROJECT_ID'],
#                                     instance=name,
#                                     zone=zone)
#             response = request.execute()
#             logging.info(response)
#
#
# def annotate_instances(instances):
#     """loops through the instances and adds exclusion, age and timeout"""
#     for inst in instances:
#         # set _excluded
#         excluded = False
#         tags = inst.get('tags', {}).get('items', [])
#         inst['_tags'] = tags
#
#         for tag in tags:
#             if tag.lower() in CONFIG['SAFE_TAGS']:
#                 excluded = True
#                 break
#         inst['_excluded'] = excluded
#
#         # set _age_minutes and _timeout_expired
#         # _timeout_expired is never True for _excluded inst
#         creation = parse_iso8601tz(inst['creationTimestamp'])
#         now = datetime.datetime.now()
#         delta = now - creation
#         age_minutes = (delta.days * 24 * 60) + (delta.seconds / 60)
#         inst['_age_minutes'] = age_minutes
#         # >= comparison because seconds are truncated above.
#         if not inst['_excluded'] and age_minutes >= CONFIG['TIMEOUT']:
#             inst['_timeout_expired'] = True
#         else:
#             inst['_timeout_expired'] = False
#
#
# def list_instances():
#     """returns a list of dictionaries containing GCE instance data"""
#     request = compute.instances().aggregatedList(project=CONFIG['GCE_PROJECT_ID'])
#     response = request.execute()
#     zones = response.get('items', {})
#     instances = []
#     for zone in zones.values():
#         for instance in zone.get('instances', []):
#             instances.append(instance)
#     annotate_instances(instances)
#     return instances
#
#
# class MainHandler(webapp2.RequestHandler):
#     """index handler, displays app configuration and instance data"""
#     def get(self):
#         instances = list_instances()
#
#         data = {}
#         data['config'] = CONFIG
#         data['title'] = SAMPLE_NAME
#         data['instances'] = instances
#         data['raw_instances'] = json.dumps(instances, indent=4, sort_keys=True)
#
#         template = jinja_environment.get_template('index.html')
#         self.response.out.write(template.render(data))
#
#
# def delete_expired_instances():
#     """logs all expired instances, calls delete API when not DRY_RUN"""
#     instances = list_instances()
#
#     # filter instances, keep only expired instances
#     instances = [i for i in instances if i['_timeout_expired']]
#
#     logging.info('delete cron: %s instance%s to delete',
#                  len(instances), '' if len(instances) == 1 else 's')
#
#     for instance in instances:
#         name = instance['name']
#         zone = instance['zone'].split('/')[-1]
#         if CONFIG['DRY_RUN']:
#             logging.info("DRY_RUN, not deleted: %s", name)
#         else:
#             logging.info("DELETE: %s", name)
#             request = compute.instances().delete(
#                                     project=CONFIG['GCE_PROJECT_ID'],
#                                     instance=name,
#                                     zone=zone)
#             response = request.execute()
#             logging.info(response)
#
# class StartHandler(webapp2.RequestHandler):
#     """delete handler - HTTP endpoint for the GAE cron job"""
#     def get(self):
#         start_instance()
#
# class DeleteHandler(webapp2.RequestHandler):
#     """delete handler - HTTP endpoint for the GAE cron job"""
#     def get(self):
#         delete_expired_instances()
#
#
# app = webapp2.WSGIApplication([
#     ('/cron/start', StartHandler),
#     ('/cron/delete', DeleteHandler),
#     ('/', MainHandler),
# ], debug=True)
#
#
# # ------------------------------------------------
# # helpers
# def parse_iso8601tz(date_string):
#     """return a datetime object for a string in ISO 8601 format.
#
#     This function parses strings in exactly this format:
#     '2012-12-26T13:31:47.823-08:00'
#
#     Sadly, datetime.strptime's %z format is unavailable on many platforms,
#     so we can't use a single strptime() call.
#     """
#
#     dt = datetime.datetime.strptime(date_string[:-6],
#                                     '%Y-%m-%dT%H:%M:%S.%f')
#
#     # parse the timezone offset separately
#     delta = datetime.timedelta(minutes=int(date_string[-2:]),
#                                hours=int(date_string[-5:-3]))
#     if date_string[-6] == '-':
#         # add the delta to return to UTC time
#         dt = dt + delta
#     else:
#         dt = dt - delta
#     return dt
