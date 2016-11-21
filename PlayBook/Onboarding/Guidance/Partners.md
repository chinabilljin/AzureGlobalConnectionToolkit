#Partners#

##Onboarding with 21Variant##

You have two ways to purchase Azure services in China, either through Web-Direct or through EA.
 
For Web-Direct, you can make a purchase on http://azure.cn by using Alipay or a China UnionPay debit card, if you cannot use a credit card. The website has all of the details about China Azure in Chinese, including Web-Direct prices. You can try this link for the English translation: https://translate.google.com.hk/translate?hl=zh-CN&sl=zh-CN&tl=en&u=https%3A%2F%2Fwww.azure.cn .
 
For EA, you will need your subsidiary or a legal entity in China to sign a contract with 21vianet. The price range (ranging from A-D) can follow the existing range issued for your headquarters.  To get support from the Microsoft account team, you will need your subsidiary name, the legal entity in China, and the full name of your headquarters. The information we need is similar to other local affiliates currently enrolled in the MNC EA agreement.
 
Although the Web-Direct sign-up and payment doesn’t require your subsidiary to be a legal entity in China, we recommend that you setup the legal entity in China. The reasons for doing so are listed below:
 
- China regulations only allow 21vianet to sell Azure services to local organizations or individual customers
- All not-for-profit services and domains need to be registered (they are only open to local organizations or individuals in China)
- EA pricing is issued by local LSS (Licensing Sales Specialist). The local sales owner will be involved, and LSS only serves customers that are legal entities (Regulation/Law in Chinese: http://www.beian123.org.cn/news.php?id=1380 )

##Billing and Subscriptions##

*A Subscription for China Azure is the same concept as for Global Azure*:
https://www.azure.cn/support/faq/#What-is-the-relationship-between-accounts-and-subscriptions

With Azure, a subscription is like a SIM card. For example, users can have two subscriptions, ABC and XYZ, and create and use Azure services under these two different subscriptions. By the end of the month, the Azure billing system will produce a detailed list of usage as follows:

- Under the user ABC subscription, the total cost for the consumption of the number of virtual machines, the total cost for storage used and the total cost of SQL Database consumption, etc.
- Similarly display the cost details for the XYZ subscription.
- Finally, the overall cost for all subscriptions.

*Note: Only users with advanced online services agreements or users with standard online services agreements can create an unlimited number of subscriptions. Other users, such as test users, can only create and use one subscription*.

*Relationship of accounts and subscriptions*

Withn Azure, there is a many-to-many relationship between accounts and subscriptions. For example, suppose there are two subscriptions, ABC and XYZ, account administrators can create several accounts as follows:

Serial No. | Subscription | Account
---------- | ---------- | ----------
1 | ABC | xiaozhang@contoso.partner.onmschina.cn
2 | XYZ | mike@contoso.partner.onmschina.cn
3 | XYZ | tom@contoso.partner.onmschina.cn
4 | XYZ | xiaozhang@contoso.partner.onmschina.cn

As listed above, xiaozhang can use Azure services under two different subscriptions (i.e. allow the same user for multiple subscriptions), while Tom and Mike can only use one subscription. There can also be multiple accounts under a single subscription.
 
For enterprise customers, accounts and subscriptions can facilitate internal cost accounting. For example, the Contoso Corporation has a software development center based in three cities: Beijing, Shanghai and Hangzhou. Contoso and 21Vianet signed a commercial Azure contract under a single Org ID: Consoto, as a result the Contoso administrator can create three subscriptions (each with a different account) for the three development centers, and have separate cost details on their Azure bill.

##Invoice and Tax##

An invoice (‘fapiao’ in China) can be applied for 3 working days after the payment is settled. The procedure is simple. L og into account.windowsazure.cn, click “subscribe”, then "payment history", then "Invoice Management" to apply for registration. For details, please refer to: http://www.21vbluecloud.com/communities/FAQ/fapiao/234.html
 
There are two kinds of invoices: a special value-added tax (VAT) invoice and a general VAT invoice. You can fill in the invoices (payable) based on your needs, and according to China government regulations, the tax you have to pay is 6%.

Let's move to the next stage - [Optimizing Stage](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Optimizing/Guidance/Guidance.md) .




 
 
