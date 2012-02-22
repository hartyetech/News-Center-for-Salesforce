global class NCRemotes {
    
  @RemoteAction
    global static List<string> searchTermSuggest(string qry){
        list<string> suggest = new list<string>();
        
    //test comment
    // create the filter text
    String filter = ' like \'%' + String.escapeSingleQuotes(qry) + '%\'';
    //begin building the dynamic soql query
    String soql = 'select id, Name';

    // add the object and filter by name to the soql
    soql += ' from Google_Alert__c where name' + filter;

    soql += ' limit 5';

    try {
      for(Google_Alert__c a : Database.query(soql))
      {
        suggest.add(a.Name);
      }
    }catch (QueryException e) {
      return null;
    }
    return suggest;
    }
    
    @RemoteAction
    global static boolean addInterest(string searchTerm){
    if(searchTerm != null && searchTerm.length() > 1){
      //see if term exists already in db
      
      Google_Alert__c alert;
      
      for(Google_Alert__c a:[select id, name from Google_Alert__c where name=:searchTerm limit 1]){
        alert=a;
      }
      
      //if we didn't find one in the db...
      if(alert==null){
        system.debug('***Inserting new alert');    
        alert = new Google_Alert__c();
        alert.name = searchTerm;
        insert alert;
      }
      
      //follow the record on chatter
      EntitySubscription follow;
      
      for(EntitySubscription s:[select id,subscriberid,parentId from EntitySubscription where parentId=:alert.id and subscriberId = :UserInfo.getUserId()]){
        follow=s;
      }
      
      if(follow==null){
        follow = new EntitySubscription(parentId = alert.id, subscriberid = UserInfo.getUserId());
        insert follow;
        return true;
      }else{
        return false;
      }
    }else{
        return false;
    }       
    }
    
    @RemoteAction
    global static boolean removeInterest(string intId){
    	try {
	    	EntitySubscription sub = [select id from EntitySubscription where parentId=:intId and subscriberId=:UserInfo.getUserId()];
	    	delete sub;
	    	return true;
    	}catch(exception e){
    		return false;
    	}
    }
    
    @RemoteAction
    global static list<Google_Alert__c> getAllInterests(){
      list<Google_Alert__c>interests=new list<Google_Alert__c>();
      for(Google_Alert__c a:[select id,Name from Google_Alert__c limit 10000]){
        interests.add(a);
      }
      
      return interests;
    }
    
	  @RemoteAction
	  global static list<Google_Alert__c> getInterests(){
	    list<Google_Alert__c>interests=new list<Google_Alert__c>();
	    for(EntitySubscription s:[select id,parentId,parent.Name from EntitySubscription where Parent.Type='Google_Alert__c' and subscriberId=:UserInfo.getUserId()]){
	      interests.add(New Google_Alert__c(id=s.ParentId,Name=s.Parent.Name));
	    }
	    
	    system.debug(interests);
	    
	    return interests;
	  }
	  
	  @RemoteAction
	  global static list<Google_Alert_Result__c> getInterestResults(list<string> filters, integer resultsOnPage){
	  	list<Google_Alert_Result__c> returnResults = new list<Google_Alert_Result__c>();
	  	//find out which alerts the user is subscribed to.	  	
	  	set<id>alertIds=new set<id>();
	  	for(EntitySubscription s:[select id,parentId from EntitySubscription where Parent.Type='Google_Alert__c' and subscriberId=:UserInfo.getUserId()]){
	  		alertIds.add(s.parentId);
	  	}
	  	
	  	string resultQuery = 'select Id,Name,URL__c,Google_Alert__c,Google_Alert__r.Name,Created_Date_Formatted__c, Source_URL__c from Google_Alert_Result__c where Google_Alert__c in :alertIds';
	  		  	
	  	if(filters != null && !filters.isempty()){
        resultQuery += (' AND Google_Alert__r.Name in :filters'); 
	  	}
	  	
	  	resultQuery += ' order by CreatedDate Desc';
	  	
	  	string queryLimit = ' limit ' + string.valueOf(resultsOnPage + 30);
	  	
	  	resultQuery += queryLimit;
	  	
	  	//get associated results for alerts
	  	integer i = 1;
	  	
	  	for(Google_Alert_Result__c r:database.query(resultQuery)){
	  		//an inefficient way to accomplis offset functionality. Real offset being added in spring 12.
	  		if(i>resultsOnPage)returnResults.add(r);
	  		
	  		i++;
	  	}
	  	
	  	return returnResults;
	  }
	  
	  @RemoteAction
	  global static integer getFeedCount(id resultId){
	  	integer feedCount = 0;
	  	for(Google_Alert_Result__Feed f:[select id,CommentCount from Google_Alert_Result__Feed where parentId=:resultId AND type != 'TrackedChange']){
	  		feedCount += (1 + f.CommentCount);
	  	}
	  	return feedCount;
	  }
	  
    @RemoteAction
    global static List<Google_Alert_Result__c> getActiveStories(){
      List<Google_Alert_Result__c>active = new List<Google_Alert_Result__c>();
      set<id> resIds = new set<id>();
      for(Google_Alert_Result__Feed f:[select id,ParentId from Google_Alert_Result__Feed where type != 'TrackedChange' order by CreatedDate desc limit 15]){
        if(!resIds.contains(f.ParentId)){
        	 resIds.add(f.ParentId);
        }  
      }
      for(Google_Alert_Result__c r:[select Id,Name,URL__c,Google_Alert__c,Google_Alert__r.Name,Created_Date_Formatted__c, Source_URL__c from Google_Alert_Result__c where id in :resIds]){
      	active.add(r);
      }
      
      return active;
    }
	  
	  @RemoteAction
	  global static boolean chatterFollower(id itemId){
	  	return([select count() from EntitySubscription where parentId=:itemId and subscriberId=:UserInfo.getUserId()] > 0);
	  }
	  
	  @RemoteAction
	  global static boolean toggleChatterFollow(id itemId){
	  	EntitySubscription sub;
	  	for(EntitySubscription s:[select id from EntitySubscription where parentId=:itemId and subscriberId=:UserInfo.getUserId()]){
	  		sub=s;
	  	}
	  	
	  	if(sub != null){
	  		delete sub;
	  		return false;
	  	}else{
        sub = new EntitySubscription(parentId = itemId, subscriberid = UserInfo.getUserId());
        insert sub;	  
        return true;		
	  	}
	  }
	  
	  @RemoteAction
	  global static List<Google_Alert__c> getRecentInterests(){
	  	List<Google_Alert__c>recentInterests = new List<Google_Alert__c>();
	  	for(Google_Alert__c a:[select id,name from Google_Alert__c order by CreatedDate desc limit 15]){
	  		recentInterests.add(a);
	  	}
	  	return recentInterests;
	  }
}