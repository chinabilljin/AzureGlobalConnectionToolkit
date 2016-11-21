#Performance#

##China Latency Issue##

When deploying your applications, you may experience issues with the network performance due to network latency and the Great Firewall effect, you will need to find a better way to work with this issue. 
 
The connectivity speed from your administration desktop (outside of China) to the Azure China VM may be slow, although this will not happen all of the time. Take using the SSH (or secure shell) to connect to your remote server as an example. The recommendation is for you to SSH to a local Azure VM, then use this VM and SSH to the Azure China VM. By doing this workaround, you will have a faster network connection speed.

Let's move to the next section - [Partners](https://github.com/Azure/AzureGlobalConnectionCenter/edit/master/PlayBook/Onboarding/Guidance/Partners.md) .
