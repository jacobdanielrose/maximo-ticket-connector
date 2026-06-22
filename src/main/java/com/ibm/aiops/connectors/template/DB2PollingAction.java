package com.ibm.aiops.connectors.template;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.json.JSONObject;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ibm.aiops.connectors.template.model.Configuration;
import com.ibm.cp4waiops.connectors.sdk.TicketAction;
import com.ibm.cp4waiops.connectors.sdk.models.Ticket;

import io.micrometer.core.instrument.Counter;

/**
 * Polling action for extracting incidents from Maximo DB2 view via JDBC
 */
public class DB2PollingAction implements Runnable {

    private Counter actionCounter;
    private Counter actionErrorCounter;
    private Configuration config;
    private String connMode;
    private ScheduledExecutorService executorService = null;
    private TicketConnector connector;
    private AtomicBoolean stopDataCollection = new AtomicBoolean(false);
    private DB2JdbcHelper jdbcHelper;
    private TicketAction ticketAction;

    static final Logger logger = Logger.getLogger(DB2PollingAction.class.getName());
    static final String dateFormatPattern = "yyyy-MM-dd HH:mm:ss";
    private SimpleDateFormat sdf = new SimpleDateFormat(dateFormatPattern);

    public DB2PollingAction(ConnectorAction action) {
        this.actionCounter = action.getActionCounter();
        this.actionErrorCounter = action.getActionErrorCounter();
        this.config = action.getConfiguration();
        this.connMode = config.getCollectionMode();
        this.connector = action.getConnector();
        this.jdbcHelper = new DB2JdbcHelper(config);
    }

    @Override
    public void run() {
        logger.log(Level.INFO, "Starting DB2 Incident Poll Action");

        HashMap<String, String> mapping = new HashMap<String, String>();
        ticketAction = new TicketAction(connector, mapping, ConnectorConstants.TICKET_TYPE, config.getJdbcUrl(),
                connMode);

        actionCounter.increment();

        try {
            // Test connection first
            if (!jdbcHelper.testConnection()) {
                logger.log(Level.SEVERE, "Failed to connect to DB2 database");
                actionErrorCounter.increment();
                return;
            }

            if (connMode.equals(ConnectorConstants.HISTORICAL)) {
                logger.log(Level.INFO, "Start collecting historical data from DB2");
                fetchAndEmitIncidents();
                connector.triggerAlerts(ConnectorConstants.INSTANCE_HISTORICAL_DATACOLLECTION_CE_TYPE);
            } else {
                logger.log(Level.INFO, "Start collecting live data from DB2");

                // Create a single-threaded executor for periodic polling
                executorService = Executors.newSingleThreadScheduledExecutor();
                executorService.scheduleAtFixedRate(this::fetchAndEmitIncidents, 0, config.getIssueSamplingRate(),
                        TimeUnit.MINUTES);
            }
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Failed to collect data from DB2", e);
            actionErrorCounter.increment();
        }
    }

    public void stop() {
        logger.log(Level.INFO, "Stopping DB2 polling action");
        stopDataCollection.set(true);
        ticketAction.closeSearchBulkProcessor();

        if (executorService != null) {
            logger.log(Level.INFO, "Shutting down DB2 polling thread");
            executorService.shutdownNow();
            logger.log(Level.INFO, "DB2 polling stopped");
        }
    }

    /**
     * Fetch incidents from DB2 view and emit them to AIOps
     */
    private void fetchAndEmitIncidents() {
        if (stopDataCollection.get()) {
            logger.log(Level.INFO, "Data collection stopped, skipping fetch");
            return;
        }

        logger.log(Level.INFO, "Fetching incidents from DB2 view");

        Connection conn = null;
        PreparedStatement stmt = null;
        ResultSet rs = null;

        try {
            conn = jdbcHelper.getConnection();
            String query = buildQuery();

            logger.log(Level.INFO, "Executing query: " + query);

            if (connMode.equals(ConnectorConstants.HISTORICAL) && config.getStart() > 0) {
                // Historical mode with date range
                stmt = conn.prepareStatement(query);
                stmt.setTimestamp(1, new Timestamp(config.getStart()));
                if (config.getEnd() > 0) {
                    stmt.setTimestamp(2, new Timestamp(config.getEnd()));
                }
            } else {
                // Live mode - get recent incidents
                stmt = conn.prepareStatement(query);
                long lookbackTime = System.currentTimeMillis() - (config.getIssueSamplingRate() * 60 * 1000);
                stmt.setTimestamp(1, new Timestamp(lookbackTime));
            }

            rs = stmt.executeQuery();

            ArrayList<Ticket> ticketList = new ArrayList<Ticket>();
            int count = 0;

            while (rs.next() && !stopDataCollection.get()) {
                try {
                    Ticket ticket = processIncidentRow(rs);
                    if (ticket != null) {
                        ticketList.add(ticket);
                        count++;
                        actionCounter.increment();

                        // Batch insert every 100 tickets
                        if (ticketList.size() >= 100) {
                            ticketAction.insertIncident(ticketList);
                            ticketList.clear();
                            logger.log(Level.INFO, "Inserted batch of 100 incidents");
                        }
                    }
                } catch (Exception e) {
                    logger.log(Level.WARNING, "Failed to process incident row", e);
                    actionErrorCounter.increment();
                }
            }

            // Insert remaining tickets
            if (ticketList.size() > 0) {
                ticketAction.insertIncident(ticketList);
                logger.log(Level.INFO, "Inserted final batch of " + ticketList.size() + " incidents");
            }

            logger.log(Level.INFO, "Successfully fetched " + count + " incidents from DB2");

        } catch (SQLException e) {
            logger.log(Level.SEVERE, "SQL error while fetching incidents", e);
            actionErrorCounter.increment();
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error while fetching incidents", e);
            actionErrorCounter.increment();
        } finally {
            jdbcHelper.closeResources(conn, stmt, rs);
        }
    }

    /**
     * Build SQL query based on configuration and mode
     */
    private String buildQuery() {
        String viewName = config.getViewName() != null ? config.getViewName() : "INCIDENT_VIEW";
        String schema = config.getDbSchema() != null ? config.getDbSchema() : "MAXIMO";
        String fullViewName = schema + "." + viewName;

        StringBuilder query = new StringBuilder();
        query.append("SELECT ");
        query.append("TICKETID, TICKETUID, CLASS, STATUS, DESCRIPTION, ");
        query.append("DESCRIPTION_LONGDESCRIPTION, REPORTEDBY, AFFECTEDPERSON, ");
        query.append("OWNER, OWNERGROUP, SITEID, ORGID, REPORTDATE, ");
        query.append("STATUSDATE, CHANGEDATE, ACTSTART, ACTFINISH, ");
        query.append("TARGETSTART, TARGETFINISH, CLASSSTRUCTUREID, ");
        query.append("ASSETNUM, LOCATION, FAILURECODE, PRIORITY, ");
        query.append("REPORTEDPRIORITY, EXTERNALSYSTEM, EXTERNALREFID ");
        query.append("FROM ").append(fullViewName).append(" ");

        if (connMode.equals(ConnectorConstants.HISTORICAL)) {
            query.append("WHERE REPORTDATE >= ? ");
            if (config.getEnd() > 0) {
                query.append("AND REPORTDATE <= ? ");
            }
        } else {
            // Live mode - get incidents modified since last poll
            query.append("WHERE CHANGEDATE >= ? ");
        }

        query.append("ORDER BY REPORTDATE DESC");

        return query.toString();
    }

    /**
     * Process a single incident row from ResultSet and convert to Ticket
     */
    private Ticket processIncidentRow(ResultSet rs) throws Exception {
        JSONObject json = new JSONObject();

        // Map Maximo fields to AIOps Ticket fields
        String ticketId = rs.getString("TICKETID");
        String ticketUid = rs.getString("TICKETUID");

        json.put(Ticket.key_sys_id, ticketUid != null ? ticketUid : ticketId);
        json.put(Ticket.key_number, ticketId);
        json.put(Ticket.key_assigned_to, getStringOrEmpty(rs, "OWNER"));
        json.put(Ticket.key_sys_created_by, getStringOrEmpty(rs, "REPORTEDBY"));
        json.put(Ticket.key_sys_domain, getStringOrEmpty(rs, "SITEID"));
        json.put(Ticket.key_business_service, getStringOrEmpty(rs, "OWNERGROUP"));

        // Map status
        String status = rs.getString("STATUS");
        json.put(Ticket.key_state, mapMaximoStatus(status));
        json.put(Ticket.key_close_code, status);

        // Descriptions
        json.put(Ticket.key_short_description, getStringOrEmpty(rs, "DESCRIPTION"));
        String longDesc = getStringOrEmpty(rs, "DESCRIPTION_LONGDESCRIPTION");
        json.put(Ticket.key_description, longDesc.isEmpty() ? getStringOrEmpty(rs, "DESCRIPTION") : longDesc);

        json.put(Ticket.key_opened_by, getStringOrEmpty(rs, "REPORTEDBY"));
        json.put(Ticket.key_source_name, "Maximo");
        json.put(Ticket.key_sys_updated_by, getStringOrEmpty(rs, "OWNER"));
        json.put(Ticket.key_closed_by, getStringOrEmpty(rs, "OWNER"));
        json.put(Ticket.key_caller_id, getStringOrEmpty(rs, "AFFECTEDPERSON"));
        json.put(Ticket.key_sys_class_name, getStringOrEmpty(rs, "CLASS"));

        // Instance/source
        json.put(Ticket.key_instance, config.getDbHost() != null ? config.getDbHost() : "maximo");

        // Dates
        Timestamp reportDate = rs.getTimestamp("REPORTDATE");
        if (reportDate != null) {
            json.put(Ticket.key_sys_created_on, sdf.format(reportDate));
            json.put(Ticket.key_opened_at, sdf.format(reportDate));
        }

        Timestamp changeDate = rs.getTimestamp("CHANGEDATE");
        if (changeDate != null) {
            json.put(Ticket.key_sys_updated_on, sdf.format(changeDate));
        }

        Timestamp statusDate = rs.getTimestamp("STATUSDATE");
        if (statusDate != null && isClosedStatus(status)) {
            json.put(Ticket.key_closed_at, sdf.format(statusDate));
        }

        // Additional fields
        json.put(Ticket.key_impact, String.valueOf(rs.getInt("PRIORITY")));
        json.put(Ticket.key_type, getStringOrEmpty(rs, "CLASSSTRUCTUREID"));
        json.put(Ticket.key_reason, getStringOrEmpty(rs, "FAILURECODE"));

        // Connection metadata
        json.put(Ticket.key_connectionmode, connMode);
        json.put(Ticket.key_connection_id, connector.getConnectorID());

        // Build source URL
        String externalRef = getStringOrEmpty(rs, "EXTERNALREFID");
        String source = config.getUrl() != null ? config.getUrl()
                + "/ui/?event=loadapp&value=incident&additionalevent=useqbe&additionaleventvalue=ticketid=" + ticketId
                : "maximo://incident/" + ticketId;
        json.put(Ticket.key_source, source);

        // Convert to Ticket object
        ObjectMapper objectMapper = new ObjectMapper();
        Ticket ticket = objectMapper.readValue(json.toString(), Ticket.class);

        return ticket;
    }

    /**
     * Map Maximo status to AIOps status
     */
    private String mapMaximoStatus(String maximoStatus) {
        if (maximoStatus == null)
            return "Open";

        switch (maximoStatus.toUpperCase()) {
        case "CLOSED":
        case "RESOLVED":
        case "COMP":
        case "COMPLETED":
            return "Closed";
        case "INPROG":
        case "QUEUED":
        case "PENDING":
            return "In Progress";
        case "NEW":
        case "REPORTED":
            return "Open";
        case "CANCELLED":
        case "CANCEL":
            return "Cancelled";
        default:
            return "Open";
        }
    }

    /**
     * Check if status represents a closed state
     */
    private boolean isClosedStatus(String status) {
        if (status == null)
            return false;
        String upper = status.toUpperCase();
        return upper.equals("CLOSED") || upper.equals("RESOLVED") || upper.equals("COMP") || upper.equals("COMPLETED")
                || upper.equals("CANCELLED") || upper.equals("CANCEL");
    }

    /**
     * Safely get string value from ResultSet
     */
    private String getStringOrEmpty(ResultSet rs, String columnName) {
        try {
            String value = rs.getString(columnName);
            return value != null ? value : "";
        } catch (SQLException e) {
            logger.log(Level.FINE, "Column not found: " + columnName);
            return "";
        }
    }
}

// Made with Bob
