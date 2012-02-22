trigger GoogleAlertToChatterStatusChange on Account (before delete, before insert, before update) {

// Note: see http://wiki.developerforce.com/index.php/Apex_Code_Best_Practices 
//       for usage of @future and callouts 	

  //list to hold all the callout details to execute in the class @future method 
  List<String> methods = new List<String>();
  List<String> endpoints = new List<String>();
  List<String> bodies = new List<String>();

  //if delete, check GA2C Status previous: active = cancel Google Alert
  if (trigger.isDelete) {
  	for (Account a : trigger.old) {
      //generate Google Alert remove callout parameters
      methods.add('GET'); //Set HTTPRequest Method 
      endpoints.add(a.Google_Alert_Cancel_URL__c); //Set HTTPRequest Endpoint
      bodies.add(''); //Set the HTTPRequest body	
  	} //end delete for loop
  }
  //else if insert|update, check GA2C Status target
  else {
  	for (Account a : trigger.new) {
  	  //if insert or if search terms field is blank, generate it before signing up
  	  if (a.Google_Alert_Search_Term_s__c == null) {a.Google_Alert_Search_Term_s__c = a.Name; }
      //if GA2C Status target = sign up
      if (a.Google_Alerts_to_Chatter_Status__c == 'Sign Up') {
      	//generate Google Alert signup callout parameters
        methods.add('POST'); //Set HTTPRequest Method 
        endpoints.add('www.google.com/alerts/create?hl=en&gl=us');
        bodies.add('q='+a.Google_Alert_Search_Term_s__c.replace(' ','+')+'&t=1'+'&f=0'+'&l=0'+'&e='); //Set HTTPRequest body, add address later	
      	//update status -> waiting for confirmation
      	a.Google_Alerts_to_Chatter_Status__c = 'Confirming';
      }
      //else if GA2C Status target = cancel
      else if (a.Google_Alerts_to_Chatter_Status__c == 'Cancel') {
        methods.add('GET'); //Set HTTPRequest Method 
        endpoints.add(a.Google_Alert_Cancel_URL__c);
        bodies.add(''); //Set the HTTPRequest body	
        //update status -> inactive
      	a.Google_Alerts_to_Chatter_Status__c = 'Inactive';
      	a.Google_Alert_Cancel_URL__c = null;
      } // end check status target if
  	} // end insert|update for loop
  } //end delete/insert|update if

  //call the execute callout method of the GoogleAlertToChatter class
  if (endpoints.size() > 0) {
    GoogleAlertToChatter.executeGoogleAlertsCallouts(methods, endpoints, bodies);
  }
} // end trigger