# KubeCon EU 2019
This repository contains the demo code for my KubeCon EU 2019 talk about building multi-cloud clusters using WireGuard.

[![youtube](https://img.youtube.com/vi/iPz_DAOOCKA/0.jpg)](https://www.youtube.com/watch?v=iPz_DAOOCKA)

In this demo we will imagine we are a company like Nest that is running object detection processes on video captured by IoT devices.
We will run a web-app in the cloud connected to a GPU-powered image detection and labeling service in a different public cloud provider.
The web-app will stream video from the IoT device over a WireGuard connection to keep the data safe.

Specifically we will:
* create a multi-cloud cluster that spans between DigitalOcean and AWS
* create some GPU workers in AWS
* run the workload that captures video in a device on the edge, e.g. your host capturing video from the webcam
* peer the workload with the cluster in the cloud
* run a computer vision process on the video captured by the edge workload
* accelerate the computer vision using GPUs in AWS.

## Prerequisites
You will need:
* DigitalOcean and AWS accounts
* Terraform installed
* the Kilo commandline utility `kgctl` installed
* WireGuard installed

## Getting Started

Modify the provided `terraform.tfvars` file to suit your project:

```sh
$EDITOR terraform.tfvars
```

## Running

1. Create the infrastructure:
```shell
terraform init
terraform apply --auto-approve
```

2. Annotate the GPU nodes so Kilo knows they are in their own data center:
```shell
for node in $(kubectl get nodes | grep -i ip- | awk '{print $1}'); do kubectl annotate node $node kilo.squat.ai/location="aws"; done
```

3. Install the manifests:
```shell
kubectl apply -f manifests/
```

4. Create the local WireGuard link:
```shell
IFACE=wg0
sudo ip link add $IFACE type wireguard
sudo ip a add 10.5.0.1 dev $IFACE
sudo ip link set up dev $IFACE
```

5. Generate a key-pair for the WireGuard link:
```shell
wg genkey | tee privatekey | wg pubkey > publickey
```

6. Create a Kilo Peer on the cluster for the local WireGuard link:
```shell
PEER=squat
cat <<EOF | kubectl apply -f -
apiVersion: kilo.squat.ai/v1alpha1
kind: Peer
metadata:
  name: $PEER
spec:
  allowedIPs:
  - 10.5.0.1/32
  publicKey: $(cat publickey)
  persistentKeepalive: 10
EOF
```

7. Configure the cluster as a peer of the local WireGuard link:
```shell
kgctl showconf peer $PEER > peer.ini
sudo wg setconf $IFACE peer.ini
sudo wg set $IFACE private-key privatekey
```

8. Add routes to the cluster's allowed IPs:
```shell
for ip in $(kgctl showconf peer $PEER | grep AllowedIPs | cut -f 3- -d ' ' | tr -d ','); do
	sudo ip route add $ip dev $IFACE
done
```

9. Run the video capture service on the "edge":
```shell
docker run --rm --privileged -p 8080:8080 squat/kubeconeu2019 /mjpeg --bind-addr=:8080
```

10. Check out the KubeCon application in a browser!
```shell
$BROWSER $(kubectl get pods -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}' | grep kceu | cut -f 2):8080
```

11. Finally, clean everything up:
```shell
terraform destroy --auto-approve
```
