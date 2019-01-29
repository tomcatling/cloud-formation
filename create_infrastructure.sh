#!/bin/bash
set -eo pipefail

echo "Attemping to create infrastructure stack..."

aws cloudformation create-stack --stack-name e-c-notebooks-infrastructure \
--template-body file://cloudformation/infrastructure-stack.yaml \
--capabilities CAPABILITY_IAM

echo "Waiting for stack creation to finish..."

aws cloudformation wait stack-create-complete --stack-name e-c-notebooks-infrastructure

echo "Configuring notebook server. Please enter a password:"

hash=$(python -c "from notebook.auth import passwd;p=passwd();print(p)")
echo "c.NotebookApp.password = '$hash'" > docker/jupyter_notebook_config.py
echo "c.NotebookApp.password_required = True" >> docker/jupyter_notebook_config.py
echo "c.NotebookApp.allow_origin = '*'" >> docker/jupyter_notebook_config.py
echo "c.NotebookApp.open_browser = False" >> docker/jupyter_notebook_config.py
echo "c.NotebookApp.port = 8888" >> docker/jupyter_notebook_config.py
echo "c.NotebookApp.allow_root = True" >> docker/jupyter_notebook_config.py


echo "Creating a private key for SSH."

if [ ! -f ./instance_key.pem ]; then
	echo "Creating ssh key..."
	aws ec2 delete-key-pair --key-name e-c-notebooks
	sleep 2
	aws ec2 create-key-pair --key-name e-c-notebooks --query 'KeyMaterial' --output text > instance_key.pem
	sleep 2
	chmod 400 instance_key.pem
fi


if [ -z $AWS_PROFILE ]; then 
	cc_addr=$(aws cloudformation describe-stacks --stack-name e-c-notebooks-infrastructure --query \
"Stacks[0].Outputs[?ExportName=='ECNotebooks::CodeCommitAddress'].OutputValue" --output text)
else 
	cc_addr=$(AWS_PROFILE=$AWS_PROFILE aws cloudformation describe-stacks --stack-name e-c-notebooks-infrastructure --query \
"Stacks[0].Outputs[?ExportName=='ECNotebooks::CodeCommitAddress'].OutputValue" --output text)
fi

echo "Adding 'codecommit' as a remote for git..."
echo "git remote add codecommit ${cc_addr}"
git remote add codecommit ${cc_addr}

echo "Telling git to use the CodeCommit credential helper..."
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

echo "Initial push..."
echo "git push codecommit master"
git push codecommit master

echo "...done."

