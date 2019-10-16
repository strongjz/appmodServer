GOFMT_FILES?=$$(find . -not -path "./vendor/*" -type f -name '*.go')
VERSION=0.0.1
AWS_REGION=us-west-2
AWS_PROFILE=contino-personal-sandbox
GRAFANA_PASSWORD=$$(openssl rand -base64 32)

fmt:
	gofmt -w $(GOFMT_FILES)

docker_build:
	docker build -t strongjz/appmod_server:$(VERSION) .

docker_push:
	docker push strongjz/appmod_server:$(VERSION)

docker_run:
	docker run -p 8080:8080 strongjz/appmod_server:$(VERSION)

k_deploy:
	kubectl apply -f deploy.yml

deploy_kubes:
	eksctl --profile ${AWS_PROFILE} create cluster --name=appMod --nodes=3 --alb-ingress-access --region=${AWS_REGION}

delete_kubes:
	eksctl --profile ${AWS_PROFILE} --region=${AWS_REGION} delete cluster appMod

kubes_status:
	kubectl cluster-info

aws_status:
	aws sts get-caller-identity --profile ${AWS_PROFILE} --region=${AWS_REGION}

aws_auth:
	docker run -it --rm -v ~/.aws:/root/.aws \
	--env-file /Users/strongjz/Documents/code/contino/aws-google-auth/.env \
	contino/aws-google-auth:0.0.27.1

nginx_deploy:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml

nginx_l7_deploy:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/service-l7.yaml; \
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/patch-configmap-l7.yaml

helm_init:
	kubectl -n kube-system create serviceaccount tiller; \
	kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller; \
	helm init --service-account tiller; \
	sleep 5 # first one needs to wait for pod to come up

prom_deploy: helm_init
	helm install stable/prometheus-operator --name prometheus

elastic_search_deploy: aws_status
	aws es --profile ${AWS_PROFILE} --region=${AWS_REGION} create-elasticsearch-domain \
	  --domain-name kubernetes-logs \
	  --elasticsearch-version 6.3 \
	  --elasticsearch-cluster-config \
	  InstanceType=m4.large.elasticsearch,InstanceCount=2 \
	  --ebs-options EBSEnabled=true,VolumeType=standard,VolumeSize=100 \
	  --access-policies '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":["*"]},"Action":["es:*"],"Resource":"*"}]}'

elastic_search_delete:
	aws es --profile ${AWS_PROFILE} --region=${AWS_REGION} delete-elasticsearch-domain --domain-name kubernetes-logs

grafana_deploy:
	kubectl create namespace grafana; \
	AWS_PROFILE=${AWS_PROFILE} helm install stable/grafana \
		--name grafana \
		--namespace grafana \
		--set persistence.storageClassName="gp2" \
		--set adminPassword="\${GRAFANA_PASSWORD}" \
		--set datasources."datasources\.yaml".apiVersion=1 \
		--set datasources."datasources\.yaml".datasources[0].name=Prometheus \
		--set datasources."datasources\.yaml".datasources[0].type=prometheus \
		--set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.prometheus.svc.cluster.local \
		--set datasources."datasources\.yaml".datasources[0].access=proxy \
		--set datasources."datasources\.yaml".datasources[0].isDefault=true \
		--set service.type=LoadBalancer

grafana_password:
	AWS_PROFILE=${AWS_PROFILE} kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

jaeger_deploy:
	kubectl create namespace observability; \
	kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing_v1_jaeger_crd.yaml; \
	kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml; \
	kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml; \
	kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml; \
	kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml

demo: deploy_kubes nginx_l7_deploy helm_init prom_deploy elastic_search_deploy grafana_deploy jaeger_deploy k_deploy

test_install:
	pip install https://github.com/newsapps/beeswithmachineguns/archive/master.zip

test_run:
    bees up -s 4 -g public -k frakkingtoasters
    bees attack -n 10000 -c 250 -u http://www.ournewwebbyhotness.com/
    bees down

destroy: delete_kubes elastic_search_delete
