public  class EscapeVCardController {

	public string inputText {get;set;}
	Pattern LIPattern = Pattern.compile('\n');

	public string getEscapedText()
	{
		
		if (inputText!=null)
		{
			string sEscapedText=inputText.replaceAll('\n', '\n ');
			sEscapedText=sEscapedText.replaceAll(';', ',');
			return 	sEscapedText;
		}
		else return '';
	}
	
	// *******************************
	// T.E.S.T M.E.T.H.O.D.S
	// *******************************
	public static testmethod void test()
	{
		EscapeVCardController control=new EscapeVCardController();
		control.inputText='test';
		control.getEscapedText();
	}
	
}