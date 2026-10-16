package com.todoapp.integration;

import com.todoapp.service.CohereService;
import com.todoapp.service.SlackService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Full-context tests against in-memory H2: real controller + service + JPA,
 * external HTTP services (Cohere, Slack) mocked. Also verifies the DevOps
 * enablement endpoints (health + Prometheus) the pipeline and monitoring rely on.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureObservability
@ActiveProfiles("test")
class TodoApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private CohereService cohereService;
    @MockitoBean
    private SlackService slackService;

    @Test
    void crudLifecycle() throws Exception {
        String created = mockMvc.perform(post("/api/todos").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"write tests\",\"description\":\"cover api\",\"completed\":false}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNumber())
                .andReturn().getResponse().getContentAsString();
        long id = new com.fasterxml.jackson.databind.ObjectMapper().readTree(created).get("id").asLong();

        mockMvc.perform(get("/api/todos"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("write tests")));

        mockMvc.perform(put("/api/todos/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"write tests\",\"description\":\"cover api\",\"completed\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.completed").value(true));

        mockMvc.perform(delete("/api/todos/" + id)).andExpect(status().isNoContent());
    }

    @Test
    void summarize_endToEnd_withPendingTodo() throws Exception {
        mockMvc.perform(post("/api/todos").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"pending item\",\"description\":\"x\",\"completed\":false}"))
                .andExpect(status().isCreated());
        when(cohereService.summarizeText(anyString())).thenReturn("summary");
        when(slackService.sendSlackMessage(anyString())).thenReturn(true);

        mockMvc.perform(post("/api/todos/summarize"))
                .andExpect(status().isOk())
                .andExpect(content().string("Summary generated and sent to Slack successfully!"));
    }

    @Test
    void health_isUp() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void healthProbes_areExposed() throws Exception {
        mockMvc.perform(get("/actuator/health/liveness")).andExpect(status().isOk());
        mockMvc.perform(get("/actuator/health/readiness")).andExpect(status().isOk());
    }

    @Test
    void prometheusEndpoint_exposesAppAndJvmMetrics() throws Exception {
        mockMvc.perform(get("/api/todos")).andExpect(status().isOk());
        mockMvc.perform(get("/actuator/prometheus"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("jvm_memory_used_bytes")))
                .andExpect(content().string(containsString("http_server_requests_seconds")))
                .andExpect(content().string(containsString("application=\"todo-summary-assistant\"")));
    }

    @Test
    void nonExposedActuatorEndpoints_areNotAvailable() throws Exception {
        mockMvc.perform(get("/actuator/env")).andExpect(status().isNotFound());
        mockMvc.perform(get("/actuator/beans")).andExpect(status().isNotFound());
    }
}
