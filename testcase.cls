// Create the input wrapper
NearbyPropertyMapService.InputWrapper input = new NearbyPropertyMapService.InputWrapper();
input.userPrompt = '34.0016,-118.3982 within 10 miles'; // Replace with any lat/lng

// Wrap it into a list
List<NearbyPropertyMapService.InputWrapper> inputList = new List<NearbyPropertyMapService.InputWrapper>{ input };

// Call the Apex method
List<NearbyPropertyMapService.ResponseWrapper> outputList = NearbyPropertyMapService.getMapFromPrompt(inputList);

// Print the result
System.debug('🔗 Map Link Result: ' + outputList[0].result);