class_name HttpTransport
extends Node
## POSTs JSON and returns {code, body}. code 0 means the request never completed.

var timeout := 120.0


func post(url: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var error := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		return {"code": 0, "body": ""}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "body": ""}
	return {"code": int(result[1]), "body": (result[3] as PackedByteArray).get_string_from_utf8()}
