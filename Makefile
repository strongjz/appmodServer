GOFMT_FILES?=$$(find . -not -path "./vendor/*" -type f -name '*.go')
VERSION=0.0.1
AWS_REGION=us-west-2

fmt:
	gofmt -w $(GOFMT_FILES)

dockerBuild:
	docker build -t strongjz/appmod_server:$(VERSION) .

dockerPush:
	docker push strongjz/appmod_server:$(VERSION)

dockerRun:
	docker run -p 8080:8080 strongjz/appmod_server:$(VERSION)

kDeploy:
	kubectl apply -f deploy.yml

deployKubes:
    eksctl create cluster --name=appMod --nodes=3 --alb-ingress-access --region=${AWS_REGION}

deleteKubes:
    eksctl delete cluster appMod

kubesStatus:

nginxDeploy:

promDeploy:

demo:

destroy:
