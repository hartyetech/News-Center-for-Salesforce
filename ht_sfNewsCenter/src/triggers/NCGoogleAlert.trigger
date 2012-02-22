trigger NCGoogleAlert on Google_Alert__c (before delete, before insert, before update) {

  //list to hold all the callout details to execute in the class @future method 
  List<String> methods = new List<String>();
  List<String> endpoints = new List<String>();
  List<String> bodies = new List<String>();
  
  //to aid in duplicate prevention, we'll store all search terms in lower case
  if(trigger.isBefore && (trigger.isInsert || trigger.isUpdate)){
  	for (Google_Alert__c a : trigger.new) {
  		a.Name = a.Name.toLowerCase();
  	}
  }

  //if delete, check GA2C Status previous: active = cancel Google Alert
  if (trigger.isDelete) {
    for (Google_Alert__c a : trigger.old) {
      //generate Google Alert remove callout parameters
      methods.add('GET'); //Set HTTPRequest Method 
      endpoints.add(a.Cancel_URL__c); //Set HTTPRequest Endpoint
      bodies.add(''); //Set the HTTPRequest body  
    } //end delete for loop
  }
  //else if insert|update, check GA2C Status target
  else if(trigger.isInsert){
    for (Google_Alert__c a : trigger.new) {
	    //generate Google Alert signup callout parameters
	    methods.add('POST'); //Set HTTPRequest Method 
	    endpoints.add('www.google.com/alerts/create?hl=en&gl=us');
	    bodies.add('q='+a.Name.replace(' ','+')+'&t=1'+'&f=0'+'&l=0'+'&e='); //Set HTTPRequest body, add address later 
	    //update status -> waiting for confirmation
	    a.Status__c = 'Confirming';
    } // end insert|update for loop
  } //end delete/insert|update if

  //call the execute callout method of the GoogleAlertToChatter class
  if (endpoints.size() > 0) {
    NCGoogleAlert.executeGoogleAlertsCallouts(methods, endpoints, bodies);
  }
}