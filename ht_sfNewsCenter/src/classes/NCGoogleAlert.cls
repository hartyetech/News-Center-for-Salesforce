global class NCGoogleAlert implements Messaging.InboundEmailHandler {


		//class variables
		public static boolean isApexTest = false;  // Static variable that assumes a test is not running; see http://sfdc.arrowpointe.com/2009/05/01/testing-http-callouts/
		public static final String openBracket = '[';
		public static final String closeBracket = ']';
		public List<String> alertMessages = new List<String>();
    public List<String> alertURLs = new List<String>();
    public Google_Alert_Settings__c settings = [select News_Source_Blacklist__c, Max_Stories_Per_Alert__c 
                                                           from Google_Alert_Settings__c limit 1];
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
      List<Google_Alert__c> relevantGARecords;
      
      // Extract sender and text of email
      try {
      	system.debug('***Email Subject: ' + email.subject);
      	system.debug('***Email TextBody: ' + email.plainTextBody);
        emailSender = email.fromAddress;
        emailSubject = email.subject;
        emailBody = email.htmlBody;
        emailTextBody = email.plainTextBody;
      } catch (System.StringException e) {
        System.debug('Invalid Email - malformed: ' + e);
	    }
      
      // If this is a verification email from Google Alerts, do an HTTP Post callout to verify & store Alert details
      if (emailSubject == 'Click to confirm your Google Alert') {
      	system.debug('***Processing Confirmation email');
        verifyURL = parseGoogleAlertforVerifyURL(emailTextBody);
        cancelURL = parseGoogleAlertforCancelURL('new', emailTextBody);
        verifyGoogleAlert(verifyURL);
        relevantGARecords = parseGoogleAlertVerifyforGARecord(emailTextBody);
        updateAlertStatusGARecords(relevantGARecords, cancelURL);
      	result.success = true;
        
      // Else if this is an alert email, parse text and post to google alert record
      } else if (emailSubject != null && emailSubject.startsWith('Google Alert -')) {
      	system.debug('***Processing Alert email');
        relevantGARecords = parseGoogleAlertforGARecord(emailSubject);
        cancelURL = parseGoogleAlertforCancelURL('active', emailTextBody);
        if(!relevantGARecords.isEmpty()){
	        parseGoogleAlertforMessage(emailBody);
	        insertResults(relevantGARecords, alertMessages, alertURLs);
        	//if something has gotten out of sync, and we're receiving emails for an alert that hasn't been updated to active or doesn't have a cancel url,
        	//we try to fix it here.
        	checkActiveGARecordFields(relevantGARecords, cancelURL);
        }else{
        	//if google thinks we have an existing alert, but we don't, we need to cancel it
        	cancelGoogleAlert(cancelURL);
        }

        result.success = true;
        
      // Else if this is duplicate notification email, parse find account and update status
      } else if (emailSubject != null && emailSubject == 'Error: Duplicate alerts') {
      	system.debug('***Processing Dubplicate Error email');
      	relevantGARecords = parseGoogleAlertDupeforGARecord(emailTextBody);
        updateDuplicateStatusGARecords(relevantGARecords);
        result.success = true;
      	
      // Else this is not an appropriate Google Alert email	
      } else {
      	System.debug('Invalid Email - did not recognize subject line: ' + emailSubject);
        result.success = false;
      } // end email type identification if/then

      return result;
    } //end inbound email handling method
    
    //Method to ensure alerts receiving emails have been updated to active and have a cancel url
    public boolean checkActiveGARecordFields(List<Google_Alert__c>relevantGARecords, string cancelURL){
    	system.debug('***Checking GA Record fields');
    	List<Google_Alert__c>updateAlerts = new List<Google_Alert__c>();
    	for(Google_Alert__c a:relevantGARecords){
    		boolean needUpdate = false;
    		if(a.Status__c != 'Active'){
    			a.Status__c = 'Active';
    			needUpdate=true;
    		}
    		if(a.Cancel_URL__c == Null || a.Cancel_URL__c==''){
    			a.Cancel_URL__c = cancelURL;
    			needUpdate=true;
    		}
    		if(needUpdate)updateAlerts.add(a);
    	}
    	update updateAlerts;
    	return true;
    }
    
    
    // Method to parse Google Alert Verify email for the verification URL
    public String parseGoogleAlertforVerifyURL(String emailBody) {
      String verifyURL = emailBody.substring(emailBody.indexOf('http://'));
      verifyURL = verifyURL.substring(0,89);
      return verifyURL;
    } //end method to parse for verification URL
    
    // Method to parse Google Alert Verify email for the cancelation URL
    public String parseGoogleAlertforCancelURL(String stage, String emailBody) {
    	list<string>linkList = emailBody.split('http://');
    	
      String cancelURL = linkList[linkList.size()-3];
      
      //cancel urls are different for new alert emails vs active alert emails
      if(stage=='active'){
      	cancelURL = cancelURL.substring(0,139);
      }else if(stage=='new'){
      	cancelURL = cancelURL.substring(0,82);
      }
      
      
      system.debug('***Cancel URL: ' + cancelURL);
      
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
    
    // Method to HTTP Post callout to Google to cancel the alert
    public Boolean cancelGoogleAlert(String url){
    	system.debug('***Canceling Google Alert');
      List<String> methods = new List<String>();
      List<String> endpoints = new List<String>();
      List<String> bodies = new List<String>();
      methods.add('GET'); //Set HTTPRequest Method 
      endpoints.add(url); //Set HTTPRequest Endpoint
      bodies.add(''); //Set the HTTPRequest body  
      executeGoogleAlertsCallouts(methods, endpoints, bodies);
      return true;
    } //end method to cancel Google Alert
    
    // Method to parse Google Alert verification email for the relevant Account
    public List<Google_Alert__c> parseGoogleAlertVerifyforGARecord(String emailBody) {
      String alertSearchString = emailBody.substring(emailBody.indexOf(openBracket)+2,emailBody.indexOf(closeBracket)-1);
      // eliminate possible quotes in search string
      if (alertSearchString.startsWith('"') && alertSearchString.endsWith('"')) {
      	alertSearchString = alertSearchString.substring(1,alertSearchString.length()-1);
      }
      // remove elipsis in search string, included when search string is longer than 15 characters
      if (alertSearchString.contains('...')) { 
      	alertSearchString = alertSearchString.substring(0,alertSearchString.indexOf('...')-1);
      }
      List<Google_Alert__c> relevantGARecords;
      relevantGARecords = [select id, Name from Google_Alert__c where Name = :alertSearchString];
      alertSearchString = alertSearchString + '%';
      if (relevantGARecords.size() == 0) { relevantGARecords = [select id, Name from Google_Alert__c where Name like :alertSearchString]; }
      return relevantGARecords;
    } //end method to parse for Account
    
    // Update accounts GoogleAlertsToChatter status and cancel URL
    public Void updateAlertStatusGARecords(List<Google_Alert__c> relevantGARecords, String cancelURL) {
      for (Google_Alert__c a : relevantGARecords) {
      	a.Status__c = 'Active';
      	a.Cancel_URL__c = cancelURL;
      } //end for each loop
      update relevantGARecords;
    } //end method to update accounts with status
    
    // Update accounts that are still waiting on confirmation with duplicate status
    public Void updateDuplicateStatusGARecords(List<Google_Alert__c> relevantGARecords) {
      for (Integer i=0; i<relevantGARecords.size(); i++) {
      	if (relevantGARecords[i].Status__c == 'Confirming') {
      	  relevantGARecords[i].Status__c = 'Active - Duplicate Search Term';
      	} else {
      	  relevantGARecords.remove(i);
      	}	//end if/then
      } //end for each loop
      update relevantGARecords;
    } // end method to update accounts with duplicate status

    // Method to parse Google Alert email for the relevant Account
    public List<Google_Alert__c> parseGoogleAlertforGARecord(String emailSubject) {
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
      List<Google_Alert__c> relevantGARecords;
      relevantGARecords = [select id, Name, Status__c, Cancel_URL__c from Google_Alert__c where Name = :alertSearchString];
      alertSearchString = alertSearchString + '%';
      if (relevantGARecords.size() == 0) { relevantGARecords = [select id, Name, Status__c, Cancel_URL__c from Google_Alert__c where Name like :alertSearchString]; }
      return relevantGARecords;
    } //end method to parse for Account
    
    // Method to parse Google Alert duplicate notice email for the relevant Account
    public List<Google_Alert__c> parseGoogleAlertDupeforGARecord(String emailBody) {
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
      List<Google_Alert__c> relevantGARecords;
      relevantGARecords = [select id, Name from Google_Alert__c where Name = :alertSearchString];
      alertSearchString = alertSearchString + '%';
      if (relevantGARecords.size() == 0) { relevantGARecords = [select id, Name from Google_Alert__c where Name like :alertSearchString]; }
      return relevantGARecords;
    } //end method to parse for GA Record

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
    
    public boolean postChatter(List<Google_Alert__c> relevantGARecords, integer alertCount){
    	//post to each alert record's chatter feed, notifying following users of new stories
    	list<feedItem> posts = new list<feedItem>();
    	for(Google_Alert__c a : relevantGARecords){
        try {
	    		feedItem post = new feedItem();
			    post.Body = alertCount + ' new Stories added for News Center Interest: ' + a.Name;
			    post.ParentId = a.Id;
			    post.Type = 'TextPost';
			    posts.add(post);   		
        }catch(exception e) {
            System.debug('Post to chatter failed: ' + e);
            return false;
        }
    	}
    	insert posts;
    	return true;
    }
    
    // Method to filter out potential duplicate results, then insert    
    public boolean insertResults(List<Google_Alert__c> relevantGARecords, List<String> alertMessages, List<String> alertURLs) {
      //no need to run method if alerts/urls is empty
      if(!alertMessages.isEmpty() && !alertURLs.isEmpty()) {
	       //calculate the max number of stories we're able to post 
	      Integer maxStories;
	      if (settings.Max_Stories_Per_Alert__c == null || settings.Max_Stories_Per_Alert__c == 0) {
	        maxStories = alertMessages.size();
	      } else {
	        maxStories = settings.Max_Stories_Per_Alert__c.intValue();  
	      }      
	      
	      //now find which results need to be inserted
	      list<Google_Alert_Result__c> insertResults = new list<Google_Alert_Result__c>();
	      for(Google_Alert__c a:relevantGARecords){
		      for(Integer i=0; i<(maxStories); i++) {
		      	try {
		      		if (!alertMessages[i].contains('img border=') && !newsSourceBlacklist.contains(alertURLs[i].split('//')[1].split('/')[0])){
		      			Google_Alert_Result__c result = new Google_Alert_Result__c();
		      			
		      			string resultTitle = alertMessages[i];
		      			
		      			if(resultTitle.length()>80){resultTitle = resultTitle.substring(0,77) + '...';}
		      			
		      			result.Google_Alert__c = a.id;
		      			result.Name = resultTitle;
		      			result.URL__c = alertURLs[i];
		      			
		      			insertResults.add(result);
		      		} else {
	              if (maxStories < alertMessages.size()) { maxStories++; } //if a story was filtered out, don't count against the Max story limit
	            }
		      	}catch(exception e) {
	            System.debug('Creation of new result records failed: ' + e);
	            return false;
	          }          
		      }
	      }
	      insert insertResults;
	      postChatter(relevantGARecords,(insertResults.size()/relevantGARecords.size()));
	      //now we can combine the results that existed in the database (if any) with the results we inserted to link to the appropriate alert records.
	      
	           	
      }    
      return true;
    }
    
    
    // Method to post the message to the relevant Account's chatter feed
    public Boolean postChatterOLD(List<Google_Alert__c> relevantGARecords, List<String> alertMessages, List<String> alertURLs) {
     if (!alertMessages.isEmpty() && !alertURLs.isEmpty()) { //ensure we don't post if there's no messages to post
      FeedItem post;
      List<FeedItem> posts = new List<FeedItem>();
      //calculate the max number of stories to post per alert 
        Integer maxStories;
        if (settings.Max_Stories_Per_Alert__c == null || settings.Max_Stories_Per_Alert__c == 0) {
          maxStories = alertMessages.size();
        } else {
          maxStories = settings.Max_Stories_Per_Alert__c.intValue();	
        }
   	  //post on each of the relevant accounts
      for(Google_Alert__c a: relevantGARecords) {
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
          	  if (maxStories < alertMessages.size()) { maxStories++; } //if a story was filtered out, don't count against the Max story limit
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
      List<Google_Alert_Settings__c> settings = [select Email_Services_Address__c from Google_Alert_Settings__c limit 1]; 
      if (settings.size() > 0) { email = settings[0].Email_Services_Address__c; }
      else { email = ''; }
      system.debug('***Email: ' + email);
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
          system.debug('***Req Body: ' + bodies[i]);
          if (bodies[i].contains('q=')) { bodies[i] = bodies[i] + email; }
          req.setBody(bodies[i]); //Set the HTTPRequest body
      	  //execute http callout
          try {
            if (!isApexTest) { //do not execute the Apex Callout if this is running in a test see http://sfdc.arrowpointe.com/2009/05/01/testing-http-callouts/
              res = http.send(req); //Execute web service call here	
              //Helpful debug messages
              //System.debug(res.toString());
              System.debug('Callout STATUS:'+res.getStatus());
              System.debug('Callout STATUS_CODE:'+res.getStatusCode());	
              //System.debug('Callout BODY: '+res.getBody());
            }
  	      } catch(System.TypeException e) {
  	      	System.debug('Type error: ' + e);
  	      }
  	        catch(System.CalloutException e) {
			//System.debug('Callout error: ' + e + '/n Callout body: ' + res.getBody());
          } //end try/catch around callout
      	} //end null endpoint if
      } //end for loop
    } //end execute callouts method


}