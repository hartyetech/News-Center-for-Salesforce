public class NewsCenterPageController {
	
	id userId;
	string searchTerm;
	
	public NewsCenterPageController(){
		userId = userInfo.getUserId();
	}
	
	public void addInterest(){
		if(searchTerm != null && searchTerm.length() > 1){
			//see if term exists already in db
			
			Google_Alert__c alert;
			
			for(Google_Alert__c a:[select id, name from Google_Alert__c where name=:searchTerm limit 1]){
				alert=a;
			}
			
			//if we didn't find one in the db...
			if(alert==null){
				alert = new Google_Alert__c();
				alert.name = searchTerm;
				insert alert;
			}
		}
	}

}