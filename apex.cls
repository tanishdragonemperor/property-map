public with sharing class NearbyPropertyMapService {
    public class InputWrapper {
        @InvocableVariable public String userPrompt;
    }

    public class ResponseWrapper {
        @InvocableVariable public String result;
    }

    @InvocableMethod(label='Find Nearby Properties and Show Map')
    public static List<ResponseWrapper> getMapFromPrompt(List<InputWrapper> inputs) {
        String prompt = inputs[0].userPrompt;
        Pattern p = Pattern.compile('([-+]?\\d*\\.?\\d+),\\s*([-+]?\\d*\\.?\\d+).*?(\\d+).*?mile');
        Matcher m = p.matcher(prompt);

        if (!m.find()) {
            return wrap('❌ Could not understand your location or radius.');
        }

        Decimal lat = Decimal.valueOf(m.group(1));
        Decimal lng = Decimal.valueOf(m.group(2));
        Decimal radius = Decimal.valueOf(m.group(3));

        List<Listing__c> listings = [
            SELECT Name, Latitude__c, Longitude__c 
            FROM Listing__c 
            WHERE Latitude__c != null AND Longitude__c != null
        ];

        List<Listing__c> nearby = new List<Listing__c>();
        for (Listing__c l : listings) {
            if (haversine(lat, lng, l.Latitude__c, l.Longitude__c) <= radius) {
                nearby.add(l);
            }
        }

        List<String> colors = new List<String>{'red','blue','green','orange','purple','yellow','black','brown','cyan','pink'};
        Integer i = 0;

        List<Map<String, Object>> markerList = new List<Map<String, Object>>();
        for (Listing__c l : nearby) {
            Integer index = Math.mod(i, colors.size());
            String color = colors[index];

            Map<String, Object> marker = new Map<String, Object>{
                'name' => l.Name,
                'lat' => l.Latitude__c,
                'lng' => l.Longitude__c,
                'color' => color
            };
            markerList.add(marker);
            i++;
        }

        String markerJson = EncodingUtil.urlEncode(JSON.serialize(markerList), 'UTF-8');
        String mapUrl = 'https://tanishdragonemperor.github.io/property-map/map.html'
                        + '?lat=' + lat + '&lng=' + lng + '&markers=' + markerJson;

        return wrap('✅ [Click here to view properties on map](' + mapUrl + ')');
    }

    private static Double haversine(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Double R = 3958.8;
        Double dLat = ((Double)(lat2 - lat1)) * (Math.PI / 180);
        Double dLon = ((Double)(lon2 - lon1)) * (Math.PI / 180);
        Double lat1Rad = ((Double)lat1) * (Math.PI / 180);
        Double lat2Rad = ((Double)lat2) * (Math.PI / 180);
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                   Math.cos(lat1Rad) * Math.cos(lat2Rad) *
                   Math.sin(dLon / 2) * Math.sin(dLon / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    private static List<ResponseWrapper> wrap(String s) {
        ResponseWrapper r = new ResponseWrapper();
        r.result = s;
        return new List<ResponseWrapper>{ r };
    }
}
