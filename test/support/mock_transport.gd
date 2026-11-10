extends RefCounted
## Stands in for HttpTransport: records each request and returns queued replies.

var replies: Array = []
var requests: Array = []


func queue_result(result: Dictionary, code: int = 200) -> void:
	replies.append({"code": code, "body": JSON.stringify({"result": result})})


func queue_error(status: String, message: String, code: int) -> void:
	replies.append({"code": code, "body": JSON.stringify({"error": {"status": status, "message": message}})})


func queue_raw(code: int, body: String) -> void:
	replies.append({"code": code, "body": body})


func post(url: String, body: String) -> Dictionary:
	requests.append({"url": url, "body": JSON.parse_string(body)})
	await Engine.get_main_loop().process_frame
	if replies.is_empty():
		return {"code": 0, "body": ""}
	return replies.pop_front()


func last_data() -> Dictionary:
	return requests.back().body.data if not requests.is_empty() else {}
