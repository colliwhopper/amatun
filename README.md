# amatun
Binary I wrote that allows you to tunnel to AWS RDS via a PRIVATE EC2 instance

# usage prereqs
ec2 instance in private subnet that has relevant port access to RDS instance  
SSM Session Manager plugin for the AWS CLI, nc and lsof installed on client  
put your pub key into an existing (your?) IAM user, The bastion has a script to query IAM via the awscli for username / keys, bastion scrapes IAM for users to add
so you create a user in IAM, then add the SSH key to the user through IAM (like you would for git)  
private instance in EC2 and rds both tagged with amatun:true  

# usage
arg1 - ssh user  
arg2 - local aws profile  
arg3 - aws region  

# example  
./amatun -u user -p my-aws-profile -r eu-west-1  


#troubleshooting
----------
aws: error: argument --target: expected one argument
- is the private instance up? Is it tagged with amatun:true?
----------

#build
----------
#build in linux (AL2/RHEL) docker container or Mac (tested on Monterey, native)  

yum install glibc-devel wget tar xz gzip make gcc file sudo -y  
cd /usr/src  
wget http://www.datsi.fi.upm.es/~frosal/sources/shc-3.8.9.tgz  
sudo tar xzf shc-3.8.9.tgz  
cd shc-3.8.9  
make  
make install  

shc -rT -f script.sh  
file script.sh.x  
mv script.sh.x amatun  
mv ./amatun /usr/bin/amatun  
chmod +x /usr/bin/amatun  
amatun -h  

-----------
