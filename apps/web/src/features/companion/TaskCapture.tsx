import { useState } from "react";
import { Plus, X } from "lucide-react";
import { aresApi } from "@/shared/ares-api";

interface Task {
  id: string;
  title: string;
  status: string;
  priority: string;
  due_date?: string;
  estimated_minutes?: number;
  project?: string;
  notes?: string;
}

export function TaskCaptureButton() {
  const [showModal, setShowModal] = useState(false);
  const [title, setTitle] = useState("");
  const [priority, setPriority] = useState("medium");
  const [dueDate, setDueDate] = useState("");
  const [estimatedMinutes, setEstimatedMinutes] = useState("");
  const [project, setProject] = useState("");
  const [notes, setNotes] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleCapture = async () => {
    if (!title.trim()) {
      setError("Task title is required");
      return;
    }

    setLoading(true);
    setError("");

    try {
      await aresApi.POST("/api/organizer/tasks", {
        title: title.trim(),
        priority,
        due_date: dueDate || null,
        estimated_minutes: estimatedMinutes ? parseInt(estimatedMinutes) : null,
        project,
        notes,
      });

      // Reset form and close
      setTitle("");
      setPriority("medium");
      setDueDate("");
      setEstimatedMinutes("");
      setProject("");
      setNotes("");
      setShowModal(false);
    } catch (err) {
      setError(`Failed to create task: ${err}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <button
        onClick={() => setShowModal(true)}
        title="Quick capture a task"
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: "0.375rem",
          height: "2rem",
          padding: "0 0.75rem",
          borderRadius: "0.375rem",
          border: "1px solid #2a2d42",
          background: "#1e2130",
          color: "#9094b8",
          fontSize: "0.875rem",
          fontWeight: 500,
          cursor: "pointer",
          transition: "all 0.15s",
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.background = "#252840";
          e.currentTarget.style.borderColor = "#3a3d52";
          e.currentTarget.style.color = "#e2e4f0";
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.background = "#1e2130";
          e.currentTarget.style.borderColor = "#2a2d42";
          e.currentTarget.style.color = "#9094b8";
        }}
      >
        <Plus size={16} />
        <span>Task</span>
      </button>

      {showModal && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            backgroundColor: "rgba(0, 0, 0, 0.5)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
          }}
          onClick={() => setShowModal(false)}
        >
          <div
            style={{
              background: "#161822",
              border: "1px solid #2a2d42",
              borderRadius: "0.5rem",
              padding: "2rem",
              maxWidth: "500px",
              width: "90%",
              maxHeight: "90vh",
              overflowY: "auto",
              boxShadow: "0 20px 25px -5px rgba(0, 0, 0, 0.3)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.5rem" }}>
              <h2 style={{ color: "#f0f2ff", margin: 0, fontSize: "1.25rem", fontWeight: 600 }}>
                Quick Capture
              </h2>
              <button
                onClick={() => setShowModal(false)}
                style={{
                  background: "none",
                  border: "none",
                  color: "#6b7194",
                  cursor: "pointer",
                  padding: 0,
                }}
              >
                <X size={20} />
              </button>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
              {error && (
                <div style={{ color: "#ef4444", fontSize: "0.875rem", padding: "0.75rem", background: "rgba(239, 68, 68, 0.1)", borderRadius: "0.375rem" }}>
                  {error}
                </div>
              )}

              <div>
                <label style={{ display: "block", color: "#e2e4f0", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 500 }}>
                  What needs to happen?
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g., Review Q4 report"
                  style={{
                    width: "100%",
                    padding: "0.75rem",
                    borderRadius: "0.375rem",
                    border: "1px solid #252840",
                    background: "#0f1218",
                    color: "#e2e4f0",
                    fontSize: "1rem",
                    boxSizing: "border-box",
                  }}
                />
              </div>

              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "1rem" }}>
                <div>
                  <label style={{ display: "block", color: "#e2e4f0", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 500 }}>
                    Priority
                  </label>
                  <select
                    value={priority}
                    onChange={(e) => setPriority(e.target.value)}
                    style={{
                      width: "100%",
                      padding: "0.75rem",
                      borderRadius: "0.375rem",
                      border: "1px solid #252840",
                      background: "#0f1218",
                      color: "#e2e4f0",
                      fontSize: "0.875rem",
                      boxSizing: "border-box",
                    }}
                  >
                    <option value="low">Low</option>
                    <option value="medium">Medium</option>
                    <option value="high">High</option>
                  </select>
                </div>

                <div>
                  <label style={{ display: "block", color: "#e2e4f0", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 500 }}>
                    Duration (min)
                  </label>
                  <input
                    type="number"
                    value={estimatedMinutes}
                    onChange={(e) => setEstimatedMinutes(e.target.value)}
                    placeholder="30"
                    style={{
                      width: "100%",
                      padding: "0.75rem",
                      borderRadius: "0.375rem",
                      border: "1px solid #252840",
                      background: "#0f1218",
                      color: "#e2e4f0",
                      fontSize: "0.875rem",
                      boxSizing: "border-box",
                    }}
                  />
                </div>
              </div>

              <div>
                <label style={{ display: "block", color: "#e2e4f0", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 500 }}>
                  Due Date
                </label>
                <input
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                  style={{
                    width: "100%",
                    padding: "0.75rem",
                    borderRadius: "0.375rem",
                    border: "1px solid #252840",
                    background: "#0f1218",
                    color: "#e2e4f0",
                    fontSize: "0.875rem",
                    boxSizing: "border-box",
                  }}
                />
              </div>

              <div>
                <label style={{ display: "block", color: "#e2e4f0", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 500 }}>
                  Project
                </label>
                <input
                  type="text"
                  value={project}
                  onChange={(e) => setProject(e.target.value)}
                  placeholder="e.g., Marketing"
                  style={{
                    width: "100%",
                    padding: "0.75rem",
                    borderRadius: "0.375rem",
                    border: "1px solid #252840",
                    background: "#0f1218",
                    color: "#e2e4f0",
                    fontSize: "0.875rem",
                    boxSizing: "border-box",
                  }}
                />
              </div>

              <div>
                <label style={{ display: "block", color: "#e2e4f0", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 500 }}>
                  Notes
                </label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Additional context..."
                  style={{
                    width: "100%",
                    padding: "0.75rem",
                    borderRadius: "0.375rem",
                    border: "1px solid #252840",
                    background: "#0f1218",
                    color: "#e2e4f0",
                    fontSize: "0.875rem",
                    minHeight: "4rem",
                    boxSizing: "border-box",
                    fontFamily: "inherit",
                  }}
                />
              </div>

              <div style={{ display: "flex", gap: "1rem", justifyContent: "flex-end", marginTop: "1rem" }}>
                <button
                  onClick={() => setShowModal(false)}
                  style={{
                    padding: "0.75rem 1.5rem",
                    borderRadius: "0.375rem",
                    border: "1px solid #2a2d42",
                    background: "transparent",
                    color: "#9094b8",
                    cursor: "pointer",
                    fontSize: "0.875rem",
                    fontWeight: 500,
                    transition: "all 0.15s",
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.background = "#1e2130";
                    e.currentTarget.style.color = "#e2e4f0";
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.background = "transparent";
                    e.currentTarget.style.color = "#9094b8";
                  }}
                >
                  Cancel
                </button>
                <button
                  onClick={handleCapture}
                  disabled={loading}
                  style={{
                    padding: "0.75rem 1.5rem",
                    borderRadius: "0.375rem",
                    border: "none",
                    background: loading ? "#9f1239" : "#ef4444",
                    color: "#ffffff",
                    cursor: loading ? "not-allowed" : "pointer",
                    fontSize: "0.875rem",
                    fontWeight: 600,
                    transition: "all 0.15s",
                    opacity: loading ? 0.7 : 1,
                  }}
                  onMouseEnter={(e) => {
                    if (!loading) e.currentTarget.style.background = "#dc2626";
                  }}
                  onMouseLeave={(e) => {
                    if (!loading) e.currentTarget.style.background = "#ef4444";
                  }}
                >
                  {loading ? "Saving..." : "Add Task"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
