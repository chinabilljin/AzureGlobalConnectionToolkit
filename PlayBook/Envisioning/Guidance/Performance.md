#Performance#

##The Great Firewall##

The effects of internet regulation in China - widely referred to as the 'Great Firewall' - can affect whether your website or any web services you provided on the Internet can be seen or used by your intended Chinese audience.

Unless your Chinese website/web services is hosted at an appropriate location, your website may be:

- Blocked altogether
- Blocked some of the time
- Extremely slowly when loading
 
The China government-managed firewall, officially termed the "Golden Shield Project", is designed to monitor and control the content viewed by Chinese internet users. If a website contains any content deemed inappropriate by the Chinese government, it will be blocked by the Great Firewall.
 
Since all network connectivity in or outside of China must go through the Great Firewall, if you are in China accessing a site outside of China, or you are outside of China accessing a site in China, you may experience some unpredictability in network performance.

#Service Hosting Options#

With the China government-managed firewall, officially termed the "Golden Shield Project", which is designed to monitor and control the content viewed by Chinese internet users, you may have limited service hosting options.

_**Shared Server**_
 
If a website contains any content deemed inappropriate by the Chinese government, it will be blocked by the Great Firewall. With this Great Firewall effect, if your website is not hosted on a dedicated server, you may encounter the worst case scenario (e.g. if another site hosted on your shared server is banned, the whole server - your site included - is likely to be blocked). If you are hosted on a shared server outside the Chinese firewall, there is a very real and potential risk for your site to be banned at any time, and it might be beyond your control.
 
_**China Users Access Server Outside of China**_
 
You may have your service already hosted on a server outside of China, and it may be providing services to users worldwide. You would like to leverage the same service, and offer it to the users in China. First, you have to consider the differences in the market (please read [Top Things to Know](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Playbook%20Overview/Top%20Things%20to%20Know.md) ). Second, if you have to consider the latency for China users when accessing your service hosted outside of China.
 
You should avoid having your users in mainland China access services outside of mainland China on a frequent basis. Your users may experience poor response times due to network latency and the Great Firewall effect, unless your application is specifically designed and optimized for low bandwidth needs. For further information, review the recommendations under the [Performance](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Planning/Guidance/Performance.md) section within the Planning Stage.
 
_**Dedicated Server Within China**_
 
The ideal situation for most companies is to host their site using a provider based in mainland China, essentially placing you inside of the "Great Firewall of China". China Azure, operated by 21Vianet, will work with you to find the best hosting solution for your situation.


