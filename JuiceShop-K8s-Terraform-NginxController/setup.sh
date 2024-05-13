# helm install ingress-nginx ingress-nginx-4.5.2.tgz

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install nginx-ingress ingress-nginx/ingress-nginx

# applying the application resources
cd app
kubectl apply -f .

# dig the load balancer name to get the ips then add them to the hosts file /etc/hosts
# <LB first IP> juice-app.devops.com
# <LB second IP> juice-app.devops.com