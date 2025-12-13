import kopf
import kubernetes
from kubernetes import client

# Load in-cluster config when running in k8s
try:
    kubernetes.config.load_incluster_config()
except:
    kubernetes.config.load_kube_config()

apps_v1 = client.AppsV1Api()
core_v1 = client.CoreV1Api()
autoscaling_v2 = client.AutoscalingV2Api()
custom_api = client.CustomObjectsApi()
policy_v1 = client.PolicyV1Api()


def set_owner_reference(owner, obj):
    """Set owner reference for automatic cleanup"""
    obj['metadata']['ownerReferences'] = [{
        'apiVersion': 'userbuys.example.com/v1',
        'kind': 'UserBuyList',
        'name': owner['metadata']['name'],
        'uid': owner['metadata']['uid'],
        'blockOwnerDeletion': True,
        'controller': True
    }]
    return obj


@kopf.on.create('userbuys.example.com', 'v1', 'userbuylist')
def create_fn(spec, name, namespace, body, logger, **kwargs):
    logger.info(f"Creating UserBuyList: {name}")
    
    replicas = spec.get('replicas', {})
    frontend_replicas = replicas.get('frontend', 1)
    customer_facing_replicas = replicas.get('customerFacing', 2)
    customer_management_replicas = replicas.get('customerManagement', 2)
    monitoring_enabled = spec.get('monitoring', {}).get('enabled', True)
    autoscaling_enabled = spec.get('autoscaling', {}).get('enabled', True)

    # 1. ConfigMaps
    create_configmaps(namespace, body, logger)
    
    # 2. Secrets
    create_secrets(namespace, body, logger)
    
    # 3. MongoDB
    create_mongodb(namespace, body, logger)
    
    # 4. Kafka + Zookeeper
    create_kafka(namespace, body, logger)
    
    # 5. Services
    create_customer_management(namespace, body, customer_management_replicas, logger)
    create_customer_facing(namespace, body, customer_facing_replicas, logger)
    create_frontend(namespace, body, frontend_replicas, logger)
    
    # 6. Autoscaling (if enabled)
    if autoscaling_enabled:
        create_autoscaling(namespace, body, logger)
    
    # 7. PDBs
    create_pdbs(namespace, body, logger)
    
    # 8. Monitoring (if enabled)
    if monitoring_enabled:
        create_monitoring(namespace, body, logger)

    logger.info(f"UserBuyList {name} created successfully")
    return {'message': f'UserBuyList {name} created'}


def create_configmaps(namespace, owner, logger):
    logger.info("Creating ConfigMaps...")
    
    configmaps = [
        {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {'name': 'customer-facing-config', 'namespace': namespace},
            'data': {
                'PORT': '3000',
                'KAFKA_BROKER': 'kafka:9092',
                'CUSTOMER_MANAGEMENT_URL': 'http://customer-management:3001',
                'PURCHASE_TOPIC': 'purchases'
            }
        },
        {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {'name': 'customer-management-config', 'namespace': namespace},
            'data': {
                'PORT': '3001',
                'KAFKA_BROKER': 'kafka:9092',
                'PURCHASE_TOPIC': 'purchases',
                'KAFKA_GROUP_ID': 'purchase-group'
            }
        },
        {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {'name': 'user-buy-frontend-config', 'namespace': namespace},
            'data': {
                'PORT': '8080',
                'CUSTOMER_FACING_URL': 'http://customer-facing:80'
            }
        }
    ]
    
    for cm in configmaps:
        cm = set_owner_reference(owner, cm)
        try:
            core_v1.create_namespaced_config_map(namespace, cm)
            logger.info(f"Created ConfigMap: {cm['metadata']['name']}")
        except client.exceptions.ApiException as e:
            if e.status == 409:
                logger.info(f"ConfigMap {cm['metadata']['name']} already exists")
            else:
                raise


def create_secrets(namespace, owner, logger):
    logger.info("Creating Secrets...")
    
    secret = {
        'apiVersion': 'v1',
        'kind': 'Secret',
        'metadata': {'name': 'customer-management-secret', 'namespace': namespace},
        'type': 'Opaque',
        'stringData': {
            'MONGODB_URI': 'mongodb://mongodb:27017/purchases'
        }
    }
    secret = set_owner_reference(owner, secret)
    
    try:
        core_v1.create_namespaced_secret(namespace, secret)
        logger.info("Created Secret: customer-management-secret")
    except client.exceptions.ApiException as e:
        if e.status == 409:
            logger.info("Secret customer-management-secret already exists")
        else:
            raise


def create_mongodb(namespace, owner, logger):
    logger.info("Creating MongoDB...")
    
    # PVC
    pvc = {
        'apiVersion': 'v1',
        'kind': 'PersistentVolumeClaim',
        'metadata': {'name': 'mongo-data-pvc', 'namespace': namespace},
        'spec': {
            'accessModes': ['ReadWriteOnce'],
            'resources': {'requests': {'storage': '1Gi'}}
        }
    }
    pvc = set_owner_reference(owner, pvc)
    
    try:
        core_v1.create_namespaced_persistent_volume_claim(namespace, pvc)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Deployment
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'mongodb', 'namespace': namespace, 'labels': {'app': 'mongodb'}},
        'spec': {
            'replicas': 1,
            'selector': {'matchLabels': {'app': 'mongodb'}},
            'template': {
                'metadata': {'labels': {'app': 'mongodb'}},
                'spec': {
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 999,
                        'runAsGroup': 999,
                        'fsGroup': 999,
                        'fsGroupChangePolicy': 'OnRootMismatch',
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'containers': [{
                        'name': 'mongodb',
                        'image': 'mongo:7',
                        'ports': [{'containerPort': 27017, 'name': 'mongodb'}],
                        'volumeMounts': [{'name': 'mongo-data', 'mountPath': '/data/db'}],
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'readOnlyRootFilesystem': False,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'startupProbe': {
                            'tcpSocket': {'port': 27017},
                            'initialDelaySeconds': 10,
                            'periodSeconds': 5,
                            'timeoutSeconds': 2,
                            'failureThreshold': 24
                        },
                        'livenessProbe': {
                            'tcpSocket': {'port': 27017},
                            'periodSeconds': 10,
                            'timeoutSeconds': 2,
                            'failureThreshold': 3
                        },
                        'readinessProbe': {
                            'tcpSocket': {'port': 27017},
                            'periodSeconds': 5,
                            'timeoutSeconds': 2,
                            'failureThreshold': 3
                        },
                        'resources': {
                            'requests': {'cpu': '50m', 'memory': '256Mi'},
                            'limits': {'cpu': '500m', 'memory': '512Mi'}
                        },
                        'env': [{'name': 'MONGO_INITDB_DATABASE', 'value': 'userbuys'}],
                        'args': ['--wiredTigerCacheSizeGB=0.25', '--maxConns=100']
                    }],
                    'volumes': [{'name': 'mongo-data', 'persistentVolumeClaim': {'claimName': 'mongo-data-pvc'}}]
                }
            }
        }
    }
    deployment = set_owner_reference(owner, deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Service
    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'mongodb', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'mongodb'},
            'ports': [{'port': 27017, 'targetPort': 27017}]
        }
    }
    service = set_owner_reference(owner, service)
    
    try:
        core_v1.create_namespaced_service(namespace, service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("MongoDB created")


def create_kafka(namespace, owner, logger):
    logger.info("Creating Kafka + Zookeeper...")
    
    # Zookeeper Deployment
    zk_deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'zookeeper', 'namespace': namespace, 'labels': {'app': 'zookeeper'}},
        'spec': {
            'replicas': 1,
            'selector': {'matchLabels': {'app': 'zookeeper'}},
            'template': {
                'metadata': {'labels': {'app': 'zookeeper'}},
                'spec': {
                    'enableServiceLinks': False,
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 1000,
                        'runAsGroup': 1000,
                        'fsGroup': 1000,
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'containers': [{
                        'name': 'zookeeper',
                        'image': 'confluentinc/cp-zookeeper:7.8.0',
                        'ports': [{'containerPort': 2181}],
                        'env': [
                            {'name': 'ZOOKEEPER_CLIENT_PORT', 'value': '2181'},
                            {'name': 'ZOOKEEPER_TICK_TIME', 'value': '2000'}
                        ],
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'livenessProbe': {
                            'tcpSocket': {'port': 2181},
                            'initialDelaySeconds': 30,
                            'periodSeconds': 10
                        },
                        'readinessProbe': {
                            'tcpSocket': {'port': 2181},
                            'initialDelaySeconds': 10,
                            'periodSeconds': 5
                        },
                        'resources': {
                            'requests': {'cpu': '100m', 'memory': '256Mi'},
                            'limits': {'cpu': '500m', 'memory': '512Mi'}
                        }
                    }]
                }
            }
        }
    }
    zk_deployment = set_owner_reference(owner, zk_deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, zk_deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Zookeeper Service
    zk_service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'zookeeper', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'zookeeper'},
            'ports': [{'port': 2181, 'targetPort': 2181}]
        }
    }
    zk_service = set_owner_reference(owner, zk_service)
    
    try:
        core_v1.create_namespaced_service(namespace, zk_service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Kafka Deployment
    kafka_deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'kafka', 'namespace': namespace, 'labels': {'app': 'kafka'}},
        'spec': {
            'replicas': 1,
            'selector': {'matchLabels': {'app': 'kafka'}},
            'template': {
                'metadata': {'labels': {'app': 'kafka'}},
                'spec': {
                    'enableServiceLinks': False,
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 1000,
                        'runAsGroup': 1000,
                        'fsGroup': 1000,
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'containers': [{
                        'name': 'kafka',
                        'image': 'confluentinc/cp-kafka:7.8.0',
                        'ports': [{'containerPort': 9092}],
                        'env': [
                            {'name': 'KAFKA_BROKER_ID', 'value': '1'},
                            {'name': 'KAFKA_ZOOKEEPER_CONNECT', 'value': 'zookeeper:2181'},
                            {'name': 'KAFKA_LISTENERS', 'value': 'PLAINTEXT://:9092'},
                            {'name': 'KAFKA_ADVERTISED_LISTENERS', 'value': 'PLAINTEXT://kafka:9092'},
                            {'name': 'KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR', 'value': '1'},
                            {'name': 'KAFKA_AUTO_CREATE_TOPICS_ENABLE', 'value': 'true'}
                        ],
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'livenessProbe': {
                            'tcpSocket': {'port': 9092},
                            'initialDelaySeconds': 60,
                            'periodSeconds': 10
                        },
                        'readinessProbe': {
                            'tcpSocket': {'port': 9092},
                            'initialDelaySeconds': 30,
                            'periodSeconds': 5
                        },
                        'resources': {
                            'requests': {'cpu': '250m', 'memory': '512Mi'},
                            'limits': {'cpu': '1000m', 'memory': '1Gi'}
                        }
                    }]
                }
            }
        }
    }
    kafka_deployment = set_owner_reference(owner, kafka_deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, kafka_deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Kafka Service
    kafka_service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'kafka', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'kafka'},
            'ports': [{'port': 9092, 'targetPort': 9092}]
        }
    }
    kafka_service = set_owner_reference(owner, kafka_service)
    
    try:
        core_v1.create_namespaced_service(namespace, kafka_service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("Kafka + Zookeeper created")


def create_customer_management(namespace, owner, replicas, logger):
    logger.info("Creating customer-management...")
    
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'customer-management', 'namespace': namespace, 'labels': {'app': 'customer-management'}},
        'spec': {
            'replicas': replicas,
            'selector': {'matchLabels': {'app': 'customer-management'}},
            'template': {
                'metadata': {'labels': {'app': 'customer-management'}},
                'spec': {
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 1000,
                        'runAsGroup': 1000,
                        'fsGroup': 1000,
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'volumes': [{'name': 'tmp', 'emptyDir': {}}],
                    'containers': [{
                        'name': 'customer-management',
                        'image': 'ghcr.io/aliceco01/user-buy-list/customer-management:latest',
                        'imagePullPolicy': 'Always',
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'readOnlyRootFilesystem': True,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'ports': [{'containerPort': 3001}],
                        'volumeMounts': [{'name': 'tmp', 'mountPath': '/tmp'}],
                        'envFrom': [
                            {'configMapRef': {'name': 'customer-management-config'}},
                            {'secretRef': {'name': 'customer-management-secret'}}
                        ],
                        'startupProbe': {
                            'httpGet': {'path': '/health', 'port': 3001},
                            'initialDelaySeconds': 5,
                            'periodSeconds': 5,
                            'failureThreshold': 30
                        },
                        'livenessProbe': {
                            'httpGet': {'path': '/health', 'port': 3001},
                            'initialDelaySeconds': 10,
                            'periodSeconds': 10
                        },
                        'readinessProbe': {
                            'httpGet': {'path': '/health', 'port': 3001},
                            'initialDelaySeconds': 5,
                            'periodSeconds': 5
                        },
                        'resources': {
                            'requests': {'cpu': '100m', 'memory': '128Mi'},
                            'limits': {'cpu': '500m', 'memory': '256Mi'}
                        }
                    }]
                }
            }
        }
    }
    deployment = set_owner_reference(owner, deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'customer-management', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'customer-management'},
            'ports': [{'port': 3001, 'targetPort': 3001}]
        }
    }
    service = set_owner_reference(owner, service)
    
    try:
        core_v1.create_namespaced_service(namespace, service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("customer-management created")


def create_customer_facing(namespace, owner, replicas, logger):
    logger.info("Creating customer-facing...")
    
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'customer-facing', 'namespace': namespace, 'labels': {'app': 'customer-facing'}},
        'spec': {
            'replicas': replicas,
            'selector': {'matchLabels': {'app': 'customer-facing'}},
            'template': {
                'metadata': {'labels': {'app': 'customer-facing'}},
                'spec': {
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 1000,
                        'runAsGroup': 1000,
                        'fsGroup': 1000,
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'volumes': [{'name': 'tmp', 'emptyDir': {}}],
                    'containers': [{
                        'name': 'customer-facing',
                        'image': 'ghcr.io/aliceco01/user-buy-list/customer-facing:latest',
                        'imagePullPolicy': 'Always',
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'readOnlyRootFilesystem': True,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'ports': [{'containerPort': 3000}],
                        'volumeMounts': [{'name': 'tmp', 'mountPath': '/tmp'}],
                        'envFrom': [{'configMapRef': {'name': 'customer-facing-config'}}],
                        'startupProbe': {
                            'httpGet': {'path': '/health', 'port': 3000},
                            'initialDelaySeconds': 5,
                            'periodSeconds': 5,
                            'failureThreshold': 30
                        },
                        'livenessProbe': {
                            'httpGet': {'path': '/health', 'port': 3000},
                            'initialDelaySeconds': 10,
                            'periodSeconds': 10
                        },
                        'readinessProbe': {
                            'httpGet': {'path': '/health', 'port': 3000},
                            'initialDelaySeconds': 5,
                            'periodSeconds': 5
                        },
                        'resources': {
                            'requests': {'cpu': '100m', 'memory': '128Mi'},
                            'limits': {'cpu': '500m', 'memory': '256Mi'}
                        }
                    }]
                }
            }
        }
    }
    deployment = set_owner_reference(owner, deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'customer-facing', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'customer-facing'},
            'ports': [{'port': 80, 'targetPort': 3000}]
        }
    }
    service = set_owner_reference(owner, service)
    
    try:
        core_v1.create_namespaced_service(namespace, service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("customer-facing created")


def create_frontend(namespace, owner, replicas, logger):
    logger.info("Creating frontend...")
    
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'user-buy-frontend', 'namespace': namespace, 'labels': {'app': 'user-buy-frontend'}},
        'spec': {
            'replicas': replicas,
            'selector': {'matchLabels': {'app': 'user-buy-frontend'}},
            'template': {
                'metadata': {'labels': {'app': 'user-buy-frontend'}},
                'spec': {
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 1000,
                        'runAsGroup': 1000,
                        'fsGroup': 1000,
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'volumes': [{'name': 'tmp', 'emptyDir': {}}],
                    'containers': [{
                        'name': 'user-buy-frontend',
                        'image': 'ghcr.io/aliceco01/user-buy-list/user-buy-frontend:latest',
                        'imagePullPolicy': 'Always',
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'readOnlyRootFilesystem': True,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'ports': [{'containerPort': 8080}],
                        'volumeMounts': [{'name': 'tmp', 'mountPath': '/tmp'}],
                        'envFrom': [{'configMapRef': {'name': 'user-buy-frontend-config'}}],
                        'livenessProbe': {
                            'httpGet': {'path': '/', 'port': 8080},
                            'initialDelaySeconds': 5
                        },
                        'readinessProbe': {
                            'httpGet': {'path': '/', 'port': 8080},
                            'initialDelaySeconds': 3
                        },
                        'resources': {
                            'requests': {'cpu': '50m', 'memory': '64Mi'},
                            'limits': {'cpu': '250m', 'memory': '128Mi'}
                        }
                    }]
                }
            }
        }
    }
    deployment = set_owner_reference(owner, deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'user-buy-frontend', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'user-buy-frontend'},
            'ports': [{'port': 80, 'targetPort': 8080}]
        }
    }
    service = set_owner_reference(owner, service)
    
    try:
        core_v1.create_namespaced_service(namespace, service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("frontend created")


def create_autoscaling(namespace, owner, logger):
    logger.info("Creating autoscaling...")
    
    # KEDA ScaledObject for customer-management
    scaled_object = {
        'apiVersion': 'keda.sh/v1alpha1',
        'kind': 'ScaledObject',
        'metadata': {'name': 'customer-management-scaler', 'namespace': namespace},
        'spec': {
            'scaleTargetRef': {'name': 'customer-management'},
            'minReplicaCount': 2,
            'maxReplicaCount': 10,
            'pollingInterval': 15,
            'cooldownPeriod': 60,
            'triggers': [{
                'type': 'kafka',
                'metadata': {
                    'bootstrapServers': 'kafka:9092',
                    'consumerGroup': 'purchase-group',
                    'topic': 'purchases',
                    'lagThreshold': '50',
                    'activationLagThreshold': '10'
                }
            }]
        }
    }
    scaled_object = set_owner_reference(owner, scaled_object)
    
    try:
        custom_api.create_namespaced_custom_object(
            group='keda.sh',
            version='v1alpha1',
            namespace=namespace,
            plural='scaledobjects',
            body=scaled_object
        )
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # HPA for customer-facing
    hpa = {
        'apiVersion': 'autoscaling/v2',
        'kind': 'HorizontalPodAutoscaler',
        'metadata': {'name': 'customer-facing-hpa', 'namespace': namespace},
        'spec': {
            'scaleTargetRef': {
                'apiVersion': 'apps/v1',
                'kind': 'Deployment',
                'name': 'customer-facing'
            },
            'minReplicas': 2,
            'maxReplicas': 8,
            'metrics': [{
                'type': 'Resource',
                'resource': {
                    'name': 'cpu',
                    'target': {'type': 'Utilization', 'averageUtilization': 70}
                }
            }]
        }
    }
    hpa = set_owner_reference(owner, hpa)
    
    try:
        autoscaling_v2.create_namespaced_horizontal_pod_autoscaler(namespace, hpa)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # HPA for frontend
    frontend_hpa = {
        'apiVersion': 'autoscaling/v2',
        'kind': 'HorizontalPodAutoscaler',
        'metadata': {'name': 'user-buy-frontend-hpa', 'namespace': namespace},
        'spec': {
            'scaleTargetRef': {
                'apiVersion': 'apps/v1',
                'kind': 'Deployment',
                'name': 'user-buy-frontend'
            },
            'minReplicas': 1,
            'maxReplicas': 3,
            'metrics': [{
                'type': 'Resource',
                'resource': {
                    'name': 'cpu',
                    'target': {'type': 'Utilization', 'averageUtilization': 70}
                }
            }]
        }
    }
    frontend_hpa = set_owner_reference(owner, frontend_hpa)
    
    try:
        autoscaling_v2.create_namespaced_horizontal_pod_autoscaler(namespace, frontend_hpa)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("Autoscaling created")


def create_pdbs(namespace, owner, logger):
    logger.info("Creating PDBs...")
    
    pdbs = [
        {
            'apiVersion': 'policy/v1',
            'kind': 'PodDisruptionBudget',
            'metadata': {'name': 'customer-facing-pdb', 'namespace': namespace},
            'spec': {
                'maxUnavailable': 1,
                'selector': {'matchLabels': {'app': 'customer-facing'}}
            }
        },
        {
            'apiVersion': 'policy/v1',
            'kind': 'PodDisruptionBudget',
            'metadata': {'name': 'customer-management-pdb', 'namespace': namespace},
            'spec': {
                'maxUnavailable': 1,
                'selector': {'matchLabels': {'app': 'customer-management'}}
            }
        }
    ]
    
    for pdb in pdbs:
        pdb = set_owner_reference(owner, pdb)
        try:
            policy_v1.create_namespaced_pod_disruption_budget(namespace, pdb)
        except client.exceptions.ApiException as e:
            if e.status != 409:
                raise
    
    logger.info("PDBs created")


def create_monitoring(namespace, owner, logger):
    logger.info("Creating monitoring (Prometheus)...")
    
    # Prometheus ConfigMap
    prometheus_config = {
        'apiVersion': 'v1',
        'kind': 'ConfigMap',
        'metadata': {'name': 'prometheus-config', 'namespace': namespace},
        'data': {
            'prometheus.yml': '''global:
  scrape_interval: 15s
  evaluation_interval: 15s
scrape_configs:
  - job_name: 'customer-facing'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - default
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: customer-facing
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        regex: (.+)
        target_label: __address__
        replacement: $1:3000
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
  - job_name: 'customer-management'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - default
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: customer-management
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        regex: (.+)
        target_label: __address__
        replacement: $1:3001
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
'''
        }
    }
    prometheus_config = set_owner_reference(owner, prometheus_config)
    
    try:
        core_v1.create_namespaced_config_map(namespace, prometheus_config)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Prometheus PVC
    pvc = {
        'apiVersion': 'v1',
        'kind': 'PersistentVolumeClaim',
        'metadata': {'name': 'prometheus-data', 'namespace': namespace},
        'spec': {
            'accessModes': ['ReadWriteOnce'],
            'resources': {'requests': {'storage': '5Gi'}}
        }
    }
    pvc = set_owner_reference(owner, pvc)
    
    try:
        core_v1.create_namespaced_persistent_volume_claim(namespace, pvc)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Prometheus ServiceAccount
    sa = {
        'apiVersion': 'v1',
        'kind': 'ServiceAccount',
        'metadata': {'name': 'prometheus', 'namespace': namespace}
    }
    sa = set_owner_reference(owner, sa)
    
    try:
        core_v1.create_namespaced_service_account(namespace, sa)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Prometheus Deployment
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': 'prometheus', 'namespace': namespace, 'labels': {'app': 'prometheus'}},
        'spec': {
            'replicas': 1,
            'selector': {'matchLabels': {'app': 'prometheus'}},
            'template': {
                'metadata': {'labels': {'app': 'prometheus'}},
                'spec': {
                    'serviceAccountName': 'prometheus',
                    'securityContext': {
                        'runAsNonRoot': True,
                        'runAsUser': 65534,
                        'runAsGroup': 65534,
                        'fsGroup': 65534,
                        'seccompProfile': {'type': 'RuntimeDefault'}
                    },
                    'containers': [{
                        'name': 'prometheus',
                        'image': 'prom/prometheus:v3.0.1',
                        'args': [
                            '--config.file=/etc/prometheus/prometheus.yml',
                            '--storage.tsdb.path=/prometheus',
                            '--web.enable-lifecycle'
                        ],
                        'ports': [{'containerPort': 9090}],
                        'volumeMounts': [
                            {'name': 'config', 'mountPath': '/etc/prometheus'},
                            {'name': 'storage', 'mountPath': '/prometheus'}
                        ],
                        'securityContext': {
                            'allowPrivilegeEscalation': False,
                            'readOnlyRootFilesystem': True,
                            'capabilities': {'drop': ['ALL']}
                        },
                        'resources': {
                            'requests': {'cpu': '100m', 'memory': '256Mi'},
                            'limits': {'cpu': '500m', 'memory': '512Mi'}
                        }
                    }],
                    'volumes': [
                        {'name': 'config', 'configMap': {'name': 'prometheus-config'}},
                        {'name': 'storage', 'persistentVolumeClaim': {'claimName': 'prometheus-data'}}
                    ]
                }
            }
        }
    }
    deployment = set_owner_reference(owner, deployment)
    
    try:
        apps_v1.create_namespaced_deployment(namespace, deployment)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    # Prometheus Service
    service = {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': 'prometheus', 'namespace': namespace},
        'spec': {
            'selector': {'app': 'prometheus'},
            'ports': [{'port': 9090, 'targetPort': 9090}]
        }
    }
    service = set_owner_reference(owner, service)
    
    try:
        core_v1.create_namespaced_service(namespace, service)
    except client.exceptions.ApiException as e:
        if e.status != 409:
            raise
    
    logger.info("Monitoring created")


@kopf.on.delete('userbuys.example.com', 'v1', 'userbuylist')
def delete_fn(name, namespace, logger, **kwargs):
    logger.info(f"Deleting UserBuyList: {name}")
    # Owner references handle cleanup automatically
    logger.info(f"UserBuyList {name} deleted")