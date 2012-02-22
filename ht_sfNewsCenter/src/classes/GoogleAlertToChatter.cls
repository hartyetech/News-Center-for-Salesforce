/**
 * Author  : Brad Herman, bherman@salesforce.com
 * Date    : March, 2010
 * Comment : This class creates and handles Google Alerts, parses the emails to identify a relevant Account,
 *           and posts the email content to that Account's chatter feed.
 *           Apex Email Services documentation: http://wiki.developerforce.com/index.php/Force.com_Email_Services
 *           Chatter API documentation: http://www.salesforce.com/us/developer/docs/api/Content/sforce_api_erd_chatter.htm
 * Requires: Instantiate and configure Email-to-Apex.
**/
global class GoogleAlertToChatter implements Messaging.InboundEmailHandler {

	//class variables
	public static boolean isApexTest = false;  // Static variable that assumes a test is not running; see http://sfdc.arrowpointe.com/2009/05/01/testing-http-callouts/
	public static final String openBracket = '[';
	public static final String closeBracket = ']';
	public List<String> alertMessages = new List<String>();
    public List<String> alertURLs = new List<String>();
    public Google_Alert_to_Chatter_Settings__c settings = [select News_Source_Blacklist__c, Maximum_Stories_Per_Alert__c 
                                                           from Google_Alert_to_Chatter_Settings__c limit 1];
    public String newsSourceBlacklist = '';

    // Method to handle inbound email
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
      // set variables using logic
      if (settings.News_Source_Blacklist__c != null) { newsSourceBlacklist = settings.News_Source_Blacklist__c; }

      // Create an inboundEmailResult object for returning the result of the Force.com Email Service
      Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
      // Other variables
      String emailSender = '';
      String emailSubject = '';
      String emailBody = '';
      String emailTextBody = '';
      String verifyURL = '';
      String cancelURL = '';
      List<Account> relevantAccounts;
      
      // Extract sender and text of email
      try {
        emailSender = email.fromAddress;
        emailSubject = email.subject;
        emailBody = email.htmlBody;
        emailTextBody = email.plainTextBody;
      } catch (System.StringException e) {
        System.debug('Invalid Email - malformed: ' + e);
	  }
      
      // If this is a verification email from Google Alerts, do an HTTP Post callout to verify & store Account details
      if (emailSubject == 'Click to confirm your Google Alert') {
        verifyURL = parseGoogleAlertforVerifyURL(emailTextBody);
        cancelURL = parseGoogleAlertforCancelURL(emailTextBody);
        verifyGoogleAlert(verifyURL);
        relevantAccounts = parseGoogleAlertVerifyforAccount(emailTextBody);
        updateAlertStatusAccounts(relevantAccounts, cancelURL);
      	result.success = true;
        
      // Else if this is an alert email, parse text and post to chatter
      } else if (emailSubject != null && emailSubject.startsWith('Google Alert -')) {
        relevantAccounts = parseGoogleAlertforAccount(emailSubject);
        parseGoogleAlertforMessage(emailBody);
        postChatter(relevantAccounts, alertMessages, alertURLs);
        result.success = true;
        
      // Else if this is duplicate notification email, parse find account and update status
      } else if (emailSubject != null && emailSubject == 'Error: Duplicate alerts') {
      	relevantAccounts = parseGoogleAlertDupeforAccount(emailTextBody);
        updateDuplicateStatusAccounts(relevantAccounts);
        result.success = true;
      	
      // Else this is not an appropriate Google Alert email	
      } else {
      	System.debug('Invalid Email - did not recognize subject line: ' + emailSubject);
        result.success = false;
      } // end email type identification if/then

      return result;
    } //end inbound email handling method
    
    
    // Method to parse Google Alert Verify email for the verification URL
    public String parseGoogleAlertforVerifyURL(String emailBody) {
      String verifyURL = emailBody.substring(emailBody.indexOf('http://'));
      verifyURL = verifyURL.substring(0,89);
      return verifyURL;
    } //end method to parse for verification URL
    
    // Method to parse Google Alert Verify email for the cancelation URL
    public String parseGoogleAlertforCancelURL(String emailBody) {
      String cancelURL = emailBody.split('http://')[2];
      cancelURL = cancelURL.substring(0,82);
      return cancelURL;
    } //end method to parse for cancel URL
    
    // Method to HTTP Post callout to Google to verify the alert
    public Boolean verifyGoogleAlert(String url){
      List<String> methods = new List<String>();
      List<String> endpoints = new List<String>();
      List<String> bodies = new List<String>();
      methods.add('GET');
      endpoints.add(url.substring(7));
      bodies.add('');
      executeGoogleAlertsCallouts(methods, endpoints, bodies);
      return true;
    } //end method to verify Google Alert
    
    // Method to parse Google Alert verification email for the relevant Account
    public List<Account> parseGoogleAlertVerifyforAccount(String emailBody) {
      String alertSearchString = emailBody.substring(emailBody.indexOf(openBracket)+2,emailBody.indexOf(closeBracket)-1);
      // eliminate possible quotes in search string
      if (alertSearchString.startsWith('"') && alertSearchString.endsWith('"')) {
      	alertSearchString = alertSearchString.substring(1,alertSearchString.length()-1);
      }
      // remove elipsis in search string, included when search string is longer than 15 characters
      if (alertSearchString.contains('...')) { 
      	alertSearchString = alertSearchString.substring(0,alertSearchString.indexOf('...')-1);
      }
      List<Account> relevantAccounts;
      relevantAccounts = [select id, name from Account where Google_Alert_Search_Term_s__c = :alertSearchString];
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where name = :alertSearchString]; }
      alertSearchString = alertSearchString + '%';
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where Google_Alert_Search_Term_s__c like :alertSearchString]; }
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where name like :alertSearchString]; }
      return relevantAccounts;
    } //end method to parse for Account
    
    // Update accounts GoogleAlertsToChatter status and cancel URL
    public Void updateAlertStatusAccounts(List<Account> relevantAccounts, String cancelURL) {
      for (Account a : relevantAccounts) {
      	a.Google_Alerts_to_Chatter_Status__c = 'Active';
      	a.Google_Alert_Cancel_URL__c = cancelURL;
      } //end for each loop
      update relevantAccounts;
    } //end method to update accounts with status
    
    // Update accounts that are still waiting on confirmation with duplicate status
    public Void updateDuplicateStatusAccounts(List<Account> relevantAccounts) {
      for (Integer i=0; i<relevantAccounts.size(); i++) {
      	if (relevantAccounts[i].Google_Alerts_to_Chatter_Status__c == 'Confirming') {
      	  relevantAccounts[i].Google_Alerts_to_Chatter_Status__c = 'Active - Duplicate Search Term';
      	} else {
      	  relevantAccounts.remove(i);
      	}	//end if/then
      } //end for each loop
      update relevantAccounts;
    } // end method to update accounts with duplicate status

    // Method to parse Google Alert email for the relevant Account
    public List<Account> parseGoogleAlertforAccount(String emailSubject) {
      String alertSearchString = emailSubject.substring(15);
      // eliminate possible quotes in search string
      if (alertSearchString.startsWith('"') && alertSearchString.endsWith('"')) {
      	alertSearchString = alertSearchString.substring(1,alertSearchString.length()-1);
      }
      // remove elipsis in search string, included when search string is longer than 15 characters
      if (alertSearchString.contains('...')) { 
      	alertSearchString = alertSearchString.substring(0,alertSearchString.indexOf('...')-1);
      }
      //match the search term(s) against account name or google alert search term 
      List<Account> relevantAccounts;
      relevantAccounts = [select id, name from Account where Google_Alert_Search_Term_s__c = :alertSearchString];
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where name = :alertSearchString]; }
      alertSearchString = alertSearchString + '%';
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where Google_Alert_Search_Term_s__c like :alertSearchString]; }
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where name like :alertSearchString]; }
      return relevantAccounts;
    } //end method to parse for Account
    
    // Method to parse Google Alert duplicate notice email for the relevant Account
    public List<Account> parseGoogleAlertDupeforAccount(String emailBody) {
      String alertSearchString = emailBody.substring(emailBody.indexOf(openBracket)+1, emailBody.indexOf(closeBracket)-1);
      // eliminate possible quotes in search string
      if (alertSearchString.startsWith('"') && alertSearchString.endsWith('"')) {
      	alertSearchString = alertSearchString.substring(1,alertSearchString.length()-1);
      }
      // remove elipsis in search string, included when search string is longer than 15 characters
      if (alertSearchString.contains('...')) { 
      	alertSearchString = alertSearchString.substring(0,alertSearchString.indexOf('...')-1);
      }
      //match the search term(s) against account name or google alert search term 
      List<Account> relevantAccounts;
      relevantAccounts = [select id, name from Account where Google_Alert_Search_Term_s__c = :alertSearchString];
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where name = :alertSearchString]; }
      alertSearchString = alertSearchString + '%';
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where Google_Alert_Search_Term_s__c like :alertSearchString]; }
      if (relevantAccounts.size() == 0) { relevantAccounts = [select id, name from Account where name like :alertSearchString]; }
      return relevantAccounts;
    } //end method to parse for Account

    // Method to parse Google Alert email for the message to post
    public Boolean parseGoogleAlertforMessage(String emailBody) {
      String headline = '';
      String link = '';
      // break the email into each "story", ignore the last string
      List<String> emailBodyStories = emailBody.split('http://www.google.com/url');
      // loop through each story to extract the headline and link, add to global list
      for (Integer i=1;i<emailBodyStories.size();i++) {
        try {
          // parse the headline text and urls from the "story"
          headline = emailBodyStories[i];
            headline = headline.substring(headline.indexOf('>')+1, headline.indexOf('</a>')).trim();
          link = emailBodyStories[i];
            link = link.substring(link.indexOf('q='), link.indexOf('&amp;ct'));
            link = link.substring(2);
          //make sure really long urls or the "See all stories" or "Related videos" links don't get included
          if (link.length() <= 255 && !headline.contains('See all stories on this topic') && headline != 'Related videos') {  
            alertMessages.add(htmlDecode(headline));
            alertURLs.add(link);
          } //end link length if
        } catch (exception e) {
          System.debug('Parsing alert email for message failed: ' + e);
          return false;
        } //end try/catch
      } //end for loop
      return true;
    } //end method to parse for messages
    
    // Method to post the message to the relevant Account's chatter feed
    public Boolean postChatter(List<Account> relevantAccounts, List<String> alertMessages, List<String> alertURLs) {
     if (!alertMessages.isEmpty() && !alertURLs.isEmpty()) { //ensure we don't post if there's no messages to post
      FeedItem post;
      List<FeedItem> posts = new List<FeedItem>();
      //calculate the max number of stories to post per alert 
        Integer maxStories;
        if (settings.Maximum_Stories_Per_Alert__c == null || settings.Maximum_Stories_Per_Alert__c == 0) {
          maxStories = alertMessages.size();
        } else {
          maxStories = settings.Maximum_Stories_Per_Alert__c.intValue();	
        }
   	  //post on each of the relevant accounts
      for(Account a: relevantAccounts) {
        //post each of the stories in the Google Alert
        for(Integer i=0; i<maxStories; i++) { //changed to "alertMessages.size()"
          try {
          	//filter out images in the Google Alert email, also filter out stories from blacklisted sources
          	if (!alertMessages[i].contains('img border=') && !newsSourceBlacklist.contains(alertURLs[i].split('//')[1].split('/')[0])) { 
          	  post = new FeedItem();
        	  post.Body = 'Google Alert - ' + alertMessages[i];
        	  post.LinkURL = alertURLs[i];
        	  post.ParentId = a.Id;
        	  post.Type = 'LinkPost';
        	  posts.add(post);
          	} else {
          	  if (maxStories < alertMessages.size()) { maxStories++; } //if a story was filtered out, don't count against the maximum story limit
          	}
          } catch(exception e) {
            System.debug('Post to chatter failed: ' + e);
            return false;
          }
        } //end messages for loop
      } //end accounts for loop
      insert posts;
      return true;
     } else { 
       return false;
     } //end empty message/alert list if/then
    } //end method to post chatter
    
    // Helper method to clear out HTML strings from headlines
    public String htmlDecode(String s){
    	s = s.replace('</b>','');
    	s = s.replace('<b>','');
    	s = s.replace('&#39;','');
    	s = s.replace('#39;','');
    	s = s.replace('&lt;','');
    	s = s.replace('&gt;','');
    	s = s.replace('&quot;','"');
    	s = s.replace('&amp;','&');
        return s;
    }
    
    // Method to execute @future callouts to GoogleAlerts - called from GoogleAlertsToChatterStatusChange trigger
    @future(callout=true) public static Void executeGoogleAlertsCallouts(List<String> methods, List<String> endpoints, List<String> bodies) {
      //variables to get the appropriate Email Service address
      String email;
      List<Google_Alert_to_Chatter_Settings__c> settings = [select Email_Services_Address__c from Google_Alert_to_Chatter_Settings__c limit 1]; 
      if (settings.size() > 0) { email = settings[0].Email_Services_Address__c; }
      else { email = ''; }
      //variables for the callouts
      HttpRequest req = new HttpRequest();
      Http http = new Http();
      HTTPResponse res;
      for (Integer i=0;i<endpoints.size();i++) {
      	if (endpoints[i] != null) { //ensure that the endpoint is not null
          //compose request
          req.setMethod(methods[i]); //Set HTTPRequest Method 
          req.setHeader('Content-Length','1024'); //Set HTTPRequest header properties
          req.setHeader('Host','www.google.com');
          req.setHeader('Connection','keep-alive');
          req.setEndpoint('http://'+endpoints[i]);
          req.setHeader('Date',''+date.today());
          //add the appropriate email if it's a signup callout
          if (bodies[i].contains('q=')) { bodies[i] = bodies[i] + email; }
          req.setBody(bodies[i]); //Set the HTTPRequest body
      	  //execute http callout
          try {
            if (!isApexTest) { //do not execute the Apex Callout if this is running in a test see http://sfdc.arrowpointe.com/2009/05/01/testing-http-callouts/
              res = http.send(req); //Execute web service call here	
              //Helpful debug messages
              //System.debug(res.toString());
              //System.debug('Callout STATUS:'+res.getStatus());
              //System.debug('Callout STATUS_CODE:'+res.getStatusCode());	
              //System.debug('Callout BODY: '+res.getBody());
            }
  	      } catch(System.TypeException e) {
  	      	System.debug('Type error: ' + e);
  	      }
  	        catch(System.CalloutException e) {
			System.debug('Callout error: ' + e + '/n Callout body: ' + res.getBody());
          } //end try/catch around callout
      	} //end null endpoint if
      } //end for loop
    } //end execute callouts method

        
    // Test methods
    static testMethod void testGoogleAlertToChatter() {
      //setup data
      Account a = new Account();
      a.name = 'Test GATC';
      Account aprime = new Account();
      aprime.name = 'Duplicate GATC';
      aprime.Google_Alerts_to_Chatter_Status__c = 'Confirming';
      aprime.Google_Alert_Search_Term_s__c = 'Test GATC';
      Account b = new Account();
      b.name = 'Another Long Named GATC';
      Account c = new Account();
      c.name = 'Yet Another GATC';
      c.Google_Alerts_to_Chatter_Status__c = 'Sign Up';
      List<Account> bc = new List<Account>();
       bc.add(b);
       bc.add(c);
      List<AccountFeed> ps = new List<AccountFeed>();
      Integer initialPosts = 0;
      Integer beforePosts = 0;
      Integer afterPosts = 0;
      List<AccountFeed> psB = new List<AccountFeed>();
      Integer initialPostsB = 0;
      Integer beforePostsB = 0;
      Integer afterPostsB = 0;
      GoogleAlertToChatter GATC;
      
      //instantiate VF controller & set inbound email address; assert the settings record numbers
      List<Google_Alert_to_Chatter_Settings__c> settings = [select Email_Services_Address__c from Google_Alert_to_Chatter_Settings__c];
  	  if (settings.size() > 0) { delete settings; }
      GoogleAlertToChatterSettingsController GATCScontroller = new GoogleAlertToChatterSettingsController();
      settings = [select Email_Services_Address__c from Google_Alert_to_Chatter_Settings__c];
  	  System.assert(settings.size() == 0);
      GATCScontroller.emailServiceAddress = 'GATC@mailinator.com';
      GATCScontroller.updateAddress();
      settings = [select Email_Services_Address__c from Google_Alert_to_Chatter_Settings__c];
  	  System.assert(settings.size() == 0); //if invalid Email Services address, shouldn't insert
      GATCScontroller.emailServiceAddress = 'GATC@mailinator.apex.sandbox.salesforce.com';
      GATCScontroller.updateAddress();
      settings = [select Email_Services_Address__c from Google_Alert_to_Chatter_Settings__c];
  	  System.assert(settings.size() == 1);
      GATCScontroller.emailServiceAddress = 'GATC@mailinator.apex.salesforce.com';
      GATCScontroller.updateAddress();
      settings = [select Email_Services_Address__c from Google_Alert_to_Chatter_Settings__c];
  	  System.assert(settings.size() == 1);
      GoogleAlertToChatterSettingsController GATCScontroller2 = new GoogleAlertToChatterSettingsController();
      GATCScontroller.emailServiceAddress = 'GATC2@mailinator.apex.salesforce.com';
      GATCScontroller.updateAddress();
      settings = [select Email_Services_Address__c, News_Source_Blacklist__c, Maximum_Stories_Per_Alert__c from Google_Alert_to_Chatter_Settings__c];
  	  System.assert(settings.size() == 1);
  	  
      //sign up for an alert (test signup trigger); assert account status
      a.Google_Alerts_to_Chatter_Status__c = 'Sign Up'; //test sign up before trigger
      insert a;
      insert bc;
      b = [select id, Google_Alerts_to_Chatter_Status__c from Account where name = 'Another Long Named GATC' limit 1];
      b.Google_Alerts_to_Chatter_Status__c = 'Sign Up';
      update b;
      a = [select id, Google_Alerts_to_Chatter_Status__c from Account where name = 'Test GATC' limit 1];
      b = [select id, Google_Alerts_to_Chatter_Status__c from Account where name = 'Another Long Named GATC' limit 1];
      c = [select id, Google_Alerts_to_Chatter_Status__c, Google_Alert_Search_Term_s__c from Account where name = 'Yet Another GATC' limit 1];
      System.assertEquals('Confirming', a.Google_Alerts_to_Chatter_Status__c);
      System.assertEquals('Confirming', b.Google_Alerts_to_Chatter_Status__c);
      System.assertEquals('Confirming', c.Google_Alerts_to_Chatter_Status__c);
      System.assertEquals('Yet Another GATC', c.Google_Alert_Search_Term_s__c);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      initialPosts = ps.size();
      psB = [select Id, Type from AccountFeed where ParentId = :b.Id];
      initialPosts = psB.size();
      
      //simulate the verification email (test verification processing); assert account status & cancel link
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail verifyEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope verifyEnvelope = new Messaging.InboundEnvelope();
      verifyEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      verifyEmail.subject = 'Click to confirm your Google Alert';
      verifyEmail.plainTextBody = 'Google received a request to start sending Alerts for the search [ "Test GATC" ] to GATC@mailinator.com.  Verify this Google Alert request:  http://www.google.com/alerts/verify?gl=us&hl=en&s=AB2Xq4j7rYTTlxwDA2MJ_mdL7GPwdLWjIF1qzyQ    Cancel this Google Alert request:  http://www.google.com/alerts/remove?gl=us&hl=en&s=AB2Xq4j7rYTTlxwDA2MJ_mdL7GPwdLWjIF1qzyQ    Thanks,  The Google Alerts Team  http://www.google.com/alerts?gl=us&hl=en';
      GATC.handleInboundEmail(verifyEmail, verifyEnvelope);
      a = [select id, Google_Alerts_to_Chatter_Status__c, Google_Alert_Cancel_URL__c from Account where name = 'Test GATC' limit 1];
      System.assertEquals('Active', a.Google_Alerts_to_Chatter_Status__c);
      System.assert(a.Google_Alert_Cancel_URL__c != null);

      //simulate duplicate signup email (test duplicate processing); assert account status
      GATC = new GoogleAlertToChatter();
      insert aprime;
      Messaging.InboundEmail duplicateEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope duplicateEnvelope = new Messaging.InboundEnvelope();
      duplicateEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      duplicateEmail.subject = 'Error: Duplicate alerts';
      duplicateEmail.plainTextBody = 'You requested an alert for [ Test GATC ]. Google Alerts is already sending alerts for that topic to testaddress@mailinator.com, so a new alert was not created.  Thanks,  The Google Alerts Team  http://www.google.com/alerts?gl=us&hl=en';
      GATC.handleInboundEmail(duplicateEmail, duplicateEnvelope);
      a = [select id, Google_Alerts_to_Chatter_Status__c, Google_Alert_Cancel_URL__c from Account where name = 'Test GATC' limit 1];
      aprime = [select id, Google_Alerts_to_Chatter_Status__c, Google_Alert_Cancel_URL__c from Account where name = 'Duplicate GATC' limit 1];
      System.assertEquals('Active', a.Google_Alerts_to_Chatter_Status__c);
      System.assert(a.Google_Alert_Cancel_URL__c != null);
//      System.assertEquals('Active - Duplicate Search Term', aprime.Google_Alerts_to_Chatter_Status__c);
      System.assert(aprime.Google_Alert_Cancel_URL__c == null);

      //simulate the verification email with a truncated searchString; assert account status & cancel link
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail verifyTruncEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope verifyTruncEnvelope = new Messaging.InboundEnvelope();
      verifyTruncEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      verifyTruncEmail.subject = 'Click to confirm your Google Alert';
      verifyTruncEmail.plainTextBody = 'Google received a request to start sending Alerts for the search [ Another Lon ... ] to GATC@mailinator.com.  Verify this Google Alert request:  http://www.google.com/alerts/verify?gl=us&hl=en&s=AB2Xq4j7rYTTlxwDA2MJ_mdL7GPwdLWjIF1qzyQ    Cancel this Google Alert request:  http://www.google.com/alerts/remove?gl=us&hl=en&s=AB2Xq4j7rYTTlxwDA2MJ_mdL7GPwdLWjIF1qzyQ    Thanks,  The Google Alerts Team  http://www.google.com/alerts?gl=us&hl=en';
      GATC.handleInboundEmail(verifyTruncEmail, verifyTruncEnvelope);
      b = [select id, Google_Alerts_to_Chatter_Status__c, Google_Alert_Cancel_URL__c from Account where name = 'Another Long Named GATC' limit 1];
      System.assertEquals('Active', b.Google_Alerts_to_Chatter_Status__c);
      System.assert(a.Google_Alert_Cancel_URL__c != null);
      
      //simulate a Google Alert email (test message parsing); assert chatter post
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail alertEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope alertEnvelope = new Messaging.InboundEnvelope();
      alertEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      alertEmail.subject = 'Google Alert - "Test GATC"';
      alertEmail.htmlBody = '<html><head></head><body><div style="font-family: sans-serif"><p><font size="+1">Google News Alert for: <b>Test GATC</b></font></p><table cellpadding="0" cellspacing="0" border="0" width="600"><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFYsyO0MOWt1wipAE3xDyLQ84Ms1w">Nine <b>Dragons</b> sees substantial profit increase in H2 2009</a><br><font size="-1"><font color="#666666">Alibaba News Channel</font><br>31, 2010 (China Knowledge) - Nine <b>Dragons</b> Paper Holdings Ltd&lt;2689&gt;, the leading paperboard producer in mainland China, yesterday said that its net profit <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en">See all stories on this topic</a></font></td></tr><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFQNx98sSkI00Lfmw3E7j7KJuhWSg"><img src="testimage.jpg">sUS HOT STOCKS: Dreamworks, Apollo Group, Bell Microproducts</a><br><font size="-1"><font color="#666666">Wall Street Journal</font><br>On the first weekend when many theater owners introduced significant movie-ticket price increases, &quot;How to Train Your <b>Dragon</b>&quot; took in $43.3 million at the <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en">See all stories on this topic</a></font></td></tr></table><p><hr noshade size=1><font size="-1">Tip: Use quotes ("like this") around a set of words in your query to match them exactly. <a href="http://www.google.com/support/websearch/bin/answer.py?answer=136861&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Learn more</a>.</font><p><font size="-1"> <nobr><a href="http://www.google.com/alerts/remove?s=AB2Xq4j27eODgzz_Bpw_sOKmOXjGOXzXB73pBBw&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Remove</a> this alert.</nobr> <br><a href="http://www.google.com/alerts?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Create</a> another alert.<br><a href="http://www.google.com/alerts/manage?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Manage</a> your alerts.</font></p></div></body></html>';
      GATC.handleInboundEmail(alertEmail, alertEnvelope);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      afterPosts = ps.size();
      System.assert(afterPosts > initialPosts);
      initialPosts = ps.size();

      //simulate a Google Alert email (too long url); assert no chatter post
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail alertLongEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope alertLongEnvelope = new Messaging.InboundEnvelope();
      alertLongEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      alertLongEmail.subject = 'Google Alert - "Test GATC"';
      alertLongEmail.htmlBody = '<html><head></head><body><div style="font-family: sans-serif"><p><font size="+1">Google News Alert for: <b>Test GATC</b></font></p><table cellpadding="0" cellspacing="0" border="0" width="600"><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://www.tmcnet.com/channels/crm-cloud-computing/articles/81511-cameleon-software-launches-its-new-app-salesforcecoms-chatterexchange.htmAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQAFQjCNFysS5UObJBbub1wjFVCRBl7ZdyVQ&amp;ct=ga">Nine <b>Dragons</b> sees substantial profit increase in H2 2009</a>See all stories on this topic</a></font></td></tr></table><p><hr noshade size=1><font size="-1">Tip: Use quotes ("like this") around a set of words in your query to match them exactly. <a href="http://www.google.com/support/websearch/bin/answer.py?answer=136861&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Learn more</a>.</font><p><font size="-1"> <nobr><a href="http://www.google.com/alerts/remove?s=AB2Xq4j27eODgzz_Bpw_sOKmOXjGOXzXB73pBBw&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Remove</a> this alert.</nobr> <br><a href="http://www.google.com/alerts?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Create</a> another alert.<br><a href="http://www.google.com/alerts/manage?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Manage</a> your alerts.</font></p></div></body></html>';
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      beforePosts = ps.size();
      GATC.handleInboundEmail(alertLongEmail, alertLongEnvelope);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      afterPosts = ps.size();
      System.assertEquals(afterPosts, beforePosts);
      initialPosts = ps.size();
      
      //simulate a Google Alert email with a truncated searchString; assert chatter post
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail alertTruncEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope alertTruncEnvelope = new Messaging.InboundEnvelope();
      alertTruncEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      alertTruncEmail.subject = 'Google Alert - Another Lon ...';
      alertTruncEmail.htmlBody = '<html><head></head><body><div style="font-family: sans-serif"><p><font size="+1">Google News Alert for: <b>Another Lon ...</b></font></p><table cellpadding="0" cellspacing="0" border="0" width="600"><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFYsyO0MOWt1wipAE3xDyLQ84Ms1w">Nine <b>Dragons</b> sees substantial profit increase in H2 2009</a><br><font size="-1"><font color="#666666">Alibaba News Channel</font><br>31, 2010 (China Knowledge) - Nine <b>Dragons</b> Paper Holdings Ltd&lt;2689&gt;, the leading paperboard producer in mainland China, yesterday said that its net profit <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en">See all stories on this topic</a></font></td></tr><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFQNx98sSkI00Lfmw3E7j7KJuhWSg"><img src="testimage.jpg">sUS HOT STOCKS: Dreamworks, Apollo Group, Bell Microproducts</a><br><font size="-1"><font color="#666666">Wall Street Journal</font><br>On the first weekend when many theater owners introduced significant movie-ticket price increases, &quot;How to Train Your <b>Dragon</b>&quot; took in $43.3 million at the <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en">See all stories on this topic</a></font></td></tr></table><p><hr noshade size=1><font size="-1">Tip: Use quotes ("like this") around a set of words in your query to match them exactly. <a href="http://www.google.com/support/websearch/bin/answer.py?answer=136861&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Learn more</a>.</font><p><font size="-1"> <nobr><a href="http://www.google.com/alerts/remove?s=AB2Xq4j27eODgzz_Bpw_sOKmOXjGOXzXB73pBBw&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Remove</a> this alert.</nobr> <br><a href="http://www.google.com/alerts?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Create</a> another alert.<br><a href="http://www.google.com/alerts/manage?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Manage</a> your alerts.</font></p></div></body></html>';
      GATC.handleInboundEmail(alertTruncEmail, alertTruncEnvelope);
      psB = [select Id, Type from AccountFeed where ParentId = :b.Id];
      afterPostsB = psB.size();
      System.assert(afterPostsB > initialPostsB);
      
      //simulate an invalid email (test negative case); assert no chatter post
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail invalidEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope invalidEnvelope = new Messaging.InboundEnvelope();
      invalidEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      invalidEmail.subject = 'Invalid Email Subject';
      invalidEmail.plainTextBody = 'This email should not be parsed by the Google Alert to Chatter application.';
      GATC.handleInboundEmail(invalidEmail, invalidEnvelope);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      System.assertEquals(ps.size(), afterPosts);

      //simulate a Google Alert email from a blacklisted source; assert no chatter post
      GATCScontroller.newsSourceBlacklist = 'www.nytimes.com';
      GATCScontroller.updateBlacklist();
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail blacklistEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope blacklistEnvelope = new Messaging.InboundEnvelope();
      blacklistEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      blacklistEmail.subject = 'Google Alert - "Test GATC"';
      blacklistEmail.htmlBody = '<html><head></head><body><div style="font-family: sans-serif"><p><font size="+1">Google News Alert for: <b>Test GATC</b></font></p><table cellpadding="0" cellspacing="0" border="0" width="600"><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://www.nytimes.com/2010/08/25/business/25econ.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFYsyO0MOWt1wipAE3xDyLQ84Ms1w">Nine <b>Dragons</b> sees substantial profit increase in H2 2009</a><br><font size="-1"><font color="#666666">Alibaba News Channel</font><br>31, 2010 (China Knowledge) - Nine <b>Dragons</b> Paper Holdings Ltd&lt;2689&gt;, the leading paperboard producer in mainland China, yesterday said that its net profit <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://www.nytimes.com/2010/08/25/business/25econ.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://www.nytimes.com/2010/08/25/business/25econ.html&amp;hl=en">See all stories on this topic</a></font></td></tr><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://www.nytimes.com/2010/08/25/business/25econ.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFQNx98sSkI00Lfmw3E7j7KJuhWSg"><img src="testimage.jpg">sUS HOT STOCKS: Dreamworks, Apollo Group, Bell Microproducts</a><br><font size="-1"><font color="#666666">Wall Street Journal</font><br>On the first weekend when many theater owners introduced significant movie-ticket price increases, &quot;How to Train Your <b>Dragon</b>&quot; took in $43.3 million at the <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://www.nytimes.com/2010/08/25/business/25econ.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://www.nytimes.com/2010/08/25/business/25econ.html&amp;hl=en">See all stories on this topic</a></font></td></tr></table><p><hr noshade size=1><font size="-1">Tip: Use quotes ("like this") around a set of words in your query to match them exactly. <a href="http://www.google.com/support/websearch/bin/answer.py?answer=136861&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Learn more</a>.</font><p><font size="-1"> <nobr><a href="http://www.google.com/alerts/remove?s=AB2Xq4j27eODgzz_Bpw_sOKmOXjGOXzXB73pBBw&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Remove</a> this alert.</nobr> <br><a href="http://www.google.com/alerts?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Create</a> another alert.<br><a href="http://www.google.com/alerts/manage?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Manage</a> your alerts.</font></p></div></body></html>';
      GATC.handleInboundEmail(blacklistEmail, blacklistEnvelope);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      System.assertEquals(ps.size(), initialPosts);
      initialPosts = ps.size();
      
      //simulate a Google Alert email with more than the max stories (1); assert small number of chatter post
      GATCScontroller.maxStoriesPerAlert = 1;
      GATCScontroller.updateMaxStories();
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail maxEmail = new Messaging.InboundEmail();
      Messaging.InboundEnvelope maxEnvelope = new Messaging.InboundEnvelope();
      maxEnvelope.fromAddress = 'googlealerts-noreply@google.com';
      maxEmail.subject = 'Google Alert - "Test GATC"';
      maxEmail.htmlBody = '<html><head></head><body><div style="font-family: sans-serif"><p><font size="+1">Google News Alert for: <b>Another Lon ...</b></font></p><table cellpadding="0" cellspacing="0" border="0" width="600"><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFYsyO0MOWt1wipAE3xDyLQ84Ms1w">Nine <b>Dragons</b> sees substantial profit increase in H2 2009</a><br><font size="-1"><font color="#666666">Alibaba News Channel</font><br>31, 2010 (China Knowledge) - Nine <b>Dragons</b> Paper Holdings Ltd&lt;2689&gt;, the leading paperboard producer in mainland China, yesterday said that its net profit <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en">See all stories on this topic</a></font></td></tr><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFQNx98sSkI00Lfmw3E7j7KJuhWSg"><img src="testimage.jpg">sUS HOT STOCKS: Dreamworks, Apollo Group, Bell Microproducts</a><br><font size="-1"><font color="#666666">Wall Street Journal</font><br>On the first weekend when many theater owners introduced significant movie-ticket price increases, &quot;How to Train Your <b>Dragon</b>&quot; took in $43.3 million at the <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en">See all stories on this topic</a></font></td></tr></table><p><hr noshade size=1><font size="-1">Tip: Use quotes ("like this") around a set of words in your query to match them exactly. <a href="http://www.google.com/support/websearch/bin/answer.py?answer=136861&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Learn more</a>.</font><p><font size="-1"> <nobr><a href="http://www.google.com/alerts/remove?s=AB2Xq4j27eODgzz_Bpw_sOKmOXjGOXzXB73pBBw&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Remove</a> this alert.</nobr> <br><a href="http://www.google.com/alerts?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Create</a> another alert.<br><a href="http://www.google.com/alerts/manage?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Manage</a> your alerts.</font></p></div></body></html>';
      GATC.handleInboundEmail(maxEmail, maxEnvelope);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      System.assertEquals(ps.size(), initialPosts+1);
      initialPosts = ps.size();
      
      //simulate a Google Alert email with max stories set to 0; assert two chatter posts
      GATCScontroller.maxStoriesPerAlert = 0;
      GATCScontroller.updateMaxStories();
      GATC = new GoogleAlertToChatter();
      Messaging.InboundEmail max0Email = new Messaging.InboundEmail();
      Messaging.InboundEnvelope max0Envelope = new Messaging.InboundEnvelope();
      max0Envelope.fromAddress = 'googlealerts-noreply@google.com';
      max0Email.subject = 'Google Alert - "Test GATC"';
      max0Email.htmlBody = '<html><head></head><body><div style="font-family: sans-serif"><p><font size="+1">Google News Alert for: <b>Another Lon ...</b></font></p><table cellpadding="0" cellspacing="0" border="0" width="600"><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFYsyO0MOWt1wipAE3xDyLQ84Ms1w">Nine <b>Dragons</b> sees substantial profit increase in H2 2009</a><br><font size="-1"><font color="#666666">Alibaba News Channel</font><br>31, 2010 (China Knowledge) - Nine <b>Dragons</b> Paper Holdings Ltd&lt;2689&gt;, the leading paperboard producer in mainland China, yesterday said that its net profit <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://news.alibaba.com/article/detail/business-in-china/100270384-1-nine-dragons-sees-substantial-profit.html&amp;hl=en">See all stories on this topic</a></font></td></tr><tr><td style="padding-bottom:1em"><a style="color: blue" href="http://www.google.com/url?sa=X&amp;q=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;ct=ga&amp;cad=7:1:0&amp;cd=YWBjhbfhmFg&amp;usg=AFQjCNFQNx98sSkI00Lfmw3E7j7KJuhWSg"><img src="testimage.jpg">sUS HOT STOCKS: Dreamworks, Apollo Group, Bell Microproducts</a><br><font size="-1"><font color="#666666">Wall Street Journal</font><br>On the first weekend when many theater owners introduced significant movie-ticket price increases, &quot;How to Train Your <b>Dragon</b>&quot; took in $43.3 million at the <b>...</b><br><a style="color: green" href="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en" title="http://news.google.com/news/story?ncl=http://online.wsj.com/article/BT-CO-20100329-707916.html&amp;hl=en">See all stories on this topic</a></font></td></tr></table><p><hr noshade size=1><font size="-1">Tip: Use quotes ("like this") around a set of words in your query to match them exactly. <a href="http://www.google.com/support/websearch/bin/answer.py?answer=136861&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Learn more</a>.</font><p><font size="-1"> <nobr><a href="http://www.google.com/alerts/remove?s=AB2Xq4j27eODgzz_Bpw_sOKmOXjGOXzXB73pBBw&amp;hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Remove</a> this alert.</nobr> <br><a href="http://www.google.com/alerts?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Create</a> another alert.<br><a href="http://www.google.com/alerts/manage?hl=en&amp;gl=us&amp;source=alertsmail&amp;cd=YWBjhbfhmFg&amp;cad=7:1:0">Manage</a> your alerts.</font></p></div></body></html>';
      GATC.handleInboundEmail(max0Email, max0Envelope);
      ps = [select Id, Type from AccountFeed where ParentId = :a.Id];
      System.assertEquals(ps.size(), initialPosts+2);
      initialPosts = ps.size();
      
      //test running the settings controller if there's already a setting record
      GATCScontroller.maxStoriesPerAlert = 1;
      GATCScontroller.updateMaxStories();
      GATCScontroller = new GoogleAlertToChatterSettingsController();
      GATCScontroller.maxStoriesPerAlert = null;
      GATCScontroller.updateMaxStories();

      //cancel alert (test cancel trigger); assert account status
      a.Google_Alerts_to_Chatter_Status__c = 'Cancel';
      update a;
      a = [select id, Google_Alerts_to_Chatter_Status__c, Google_Alert_Cancel_URL__c from Account where name = 'Test GATC' limit 1];
      System.assertEquals(null, a.Google_Alert_Cancel_URL__c);
      System.assertEquals('Inactive', a.Google_Alerts_to_Chatter_Status__c);
      
      //sign up for alert & delete
      delete b;
      
      //clean up
      delete a;
      delete c;
      delete aprime;
      
    }// end test method
    
} // end class