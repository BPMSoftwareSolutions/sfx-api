capability project-api-estate-events
intent: Project events of the estate's live feed into the server-sent frames the hosting facade writes unchanged: one frame per event, its id the feed sequence and its data the legacy observer record {seq, receivedAt, kind, payload, api}, where api names the run, the run event identity and cursor, when it was recorded, its execution root and the run's capability. run.started and run.exited are the observer's run-start and run-end. The facade asks once per event and writes the same frame to every subscriber.
outcome: project-api-estate-events-result.v1 with one frame per event, in order
inquiry: How does each live event appear on the estate feed?
input contract project-api-estate-events-request.v1 {"type":"object","properties":{"instance":{"type":"string"},"events":{"type":"array"}}}
output contract project-api-estate-events-result.v1 {"type":"object","required":["contractId","frames"]}
cli display outcome as json
scenario project-api-estate-events root terminal
given: the feed instance and a batch of its events, each with its sequence, receipt time, run, capability and run event
when: each event is projected into its record and frame
then: the outcome is the frames, one per event, in order
operation project-api-estate-events.project kind invoke-port port project-api-estate-events-project
platform bind project-api-estate-events-project
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"object","fields":{"contractId":{"op":"literal","value":"project-api-estate-events-result.v1"},"frames":{"op":"map","from":{"op":"path","path":"events"},"as":"e","value":{"op":"format","template":"id: {seq}\ndata: {record}\n\n","values":{"seq":{"op":"path","path":"seq","from":"e"},"record":{"op":"json-stringify","value":{"op":"object","fields":{"seq":{"op":"path","path":"seq","from":"e"},"receivedAt":{"op":"path","path":"receivedAt","from":"e"},"kind":{"op":"if","when":{"op":"equals","left":{"op":"path","path":"event.kind","from":"e"},"right":{"op":"literal","value":"run.started"}},"then":{"op":"literal","value":"run-start"},"else":{"op":"if","when":{"op":"equals","left":{"op":"path","path":"event.kind","from":"e"},"right":{"op":"literal","value":"run.exited"}},"then":{"op":"literal","value":"run-end"},"else":{"op":"path","path":"event.kind","from":"e"}}},"payload":{"op":"path","path":"event.payload","from":"e"},"api":{"op":"object","fields":{"runId":{"op":"path","path":"runId","from":"e"},"eventId":{"op":"path","path":"event.eventId","from":"e"},"cursor":{"op":"path","path":"event.cursor","from":"e"},"recordedAt":{"op":"path","path":"event.at","from":"e"},"rootExecutionId":{"op":"path","path":"event.rootExecutionId","from":"e"},"subject":{"op":"object","fields":{"capabilityId":{"op":"path","path":"capability.subject","from":"e"},"namespaceId":{"op":"path","path":"capability.namespace","from":"e"}}}}}}}}}}}}}}
