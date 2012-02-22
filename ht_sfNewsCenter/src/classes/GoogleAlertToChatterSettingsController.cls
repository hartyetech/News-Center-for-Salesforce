public with sharing class GoogleAlertToChatterSettingsController {
  //class variables
  public String emailServiceAddress {get;set;}
  public Boolean showCheckMark {get;set;}
  public String newsSourceBlacklist {get;set;}
  public Boolean showBlacklistSection {get;set;}
  public Boolean showBlacklistCheckMark {get;set;}
  public Integer maxStoriesPerAlert {get;set;}
  public Boolean showMaxStoriesCheckmark {get;set;}

  public GoogleAlertToChatterSettingsController() { //constructor
  	showCheckMark = false;
  	showBlacklistCheckmark = false;
  	showMaxStoriesCheckmark = false;
  	//look to see if there's already a record in the settings object
  	List<Google_Alert_to_Chatter_Settings__c> settings = [select Email_Services_Address__c, News_Source_Blacklist__c, Maximum_Stories_Per_Alert__c
  	                                                      from Google_Alert_to_Chatter_Settings__c limit 1];
  	//if a record exists, assign the address & blacklist in the record to the address & blacklist variables
  	if (settings.size() > 0) {
  	  emailServiceAddress = settings[0].Email_Services_Address__c;
  	  newsSourceBlacklist = settings[0].News_Source_Blacklist__c;
  	  if (settings[0].Maximum_Stories_Per_Alert__c != null) { maxStoriesPerAlert = settings[0].Maximum_Stories_Per_Alert__c.intValue(); }
  	  showBlacklistSection = true;
  	}
  	//otherwise, assign a blank string to the address and don't show the blacklist section on the page
  	else {
  	  emailServiceAddress = '';
  	  showBlacklistSection = false;
  	} // end if/else
  } // end constructor

  public Void updateAddress() { //method to update emailServiceAddress
   if (emailServiceAddress.contains('.salesforce.com') || emailServiceAddress.contains('.sandbox.salesforce.com')) {
  	List<Google_Alert_to_Chatter_Settings__c> settings = [select Email_Services_Address__c
  	                                                      from Google_Alert_to_Chatter_Settings__c limit 1];
  	//if a record exists, update the address in the record
  	if (settings.size() > 0) {
  	  settings[0].Email_Services_Address__c = emailServiceAddress;
  	  try {
  	  	update settings[0];
  	  } catch (DmlException e) {
  	  	ApexPages.addMessages(e);
  	  }
  	}
  	//otherwise, insert a record with that address
  	else {
  	  Google_Alert_to_Chatter_Settings__c setting = new Google_Alert_to_Chatter_Settings__c();
  	  setting.Email_Services_Address__c = emailServiceAddress;
  	  try {
		insert setting;
  	  } catch (DmlException e) {
  	  	ApexPages.addMessages(e);
  	  }
  	} // end if/else
  	showCheckMark = true;
   } else { //if the email address does not have the right '.salesforce.com' domain (i.e. .in.salesforce.com, .apex.salesforce.com, .in.sandbox.salesforce.com)
  	ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Email address must be a valid Email Services address'));
   } // end address check
  }// end updateAddress method
  
  public Void updateBlacklist() { //method to update newsSourceBlacklist
   	List<Google_Alert_to_Chatter_Settings__c> settings = [select News_Source_Blacklist__c
  	                                                      from Google_Alert_to_Chatter_Settings__c limit 1];
    settings[0].News_Source_Blacklist__c = newsSourceBlacklist;
    try {
      update settings[0];
    } catch (DmlException e) {
  	  ApexPages.addMessages(e);
  	}
  	showBlacklistCheckMark = true;
  }// end updateBlacklist method
  
  public Void updateMaxStories() { //method to update maxStoriesPerAlert
   	if (maxStoriesPerAlert >= 0) { //check negative entries
   	  List<Google_Alert_to_Chatter_Settings__c> settings = [select Maximum_Stories_Per_Alert__c
  	                                                        from Google_Alert_to_Chatter_Settings__c limit 1];
      if (maxStoriesPerAlert == 0) { //check for max value = zero 
      	settings[0].Maximum_Stories_Per_Alert__c = null;
      	maxStoriesPerAlert = null;
      } else {
      	settings[0].Maximum_Stories_Per_Alert__c = maxStoriesPerAlert;
      } //end max value = zero check
      try {
        update settings[0];
  	    showMaxStoriesCheckmark = true;
      } catch (DmlException e) {
    	ApexPages.addMessages(e);
  	  }
   	} else {
   		maxStoriesPerAlert = null;
   		showMaxStoriesCheckmark = false;
   	}// end negative entries check
  }// end updateMaxStories method
  
}// end controller class