import { useState, useCallback } from 'react';
import {
  ReactFlow,
  Controls,
  Background,
  applyNodeChanges,
  applyEdgeChanges,
  Node,
  Edge,
  NodeChange,
  EdgeChange
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';

import { PageHeader } from "@/components/PageHeader";
import { CadViewerNode } from "@/components/CadViewerNode";

const nodeTypes = {
  cadViewer: CadViewerNode,
};

const initialNodes: Node[] = [
  {
    id: '1',
    position: { x: 300, y: 100 },
    data: { label: '🧠 Jaeger AI (Reasoning)' },
    type: 'default',
    style: { 
      background: 'var(--background)',
      border: '2px solid var(--primary)',
      borderRadius: '8px',
      padding: '12px',
      fontWeight: 'bold',
      color: 'var(--foreground)'
    }
  },
  {
    id: '2',
    position: { x: 300, y: 250 },
    data: { label: '⚙️ Hermes (Execution)' },
    type: 'default',
    style: { 
      background: 'var(--background)',
      border: '2px solid var(--secondary)',
      borderRadius: '8px',
      padding: '12px',
      color: 'var(--foreground)'
    }
  },
  {
    id: '3',
    position: { x: 600, y: 150 },
    data: { label: 'Turbine_Engine_v4.stl' },
    type: 'cadViewer',
  }
];
const initialEdges: Edge[] = [
  { id: 'e1-2', source: '1', target: '2', animated: true },
  { id: 'e2-3', source: '2', target: '3', animated: true }
];

export function CanvasPage() {
  const [nodes, setNodes] = useState<Node[]>(initialNodes);
  const [edges, setEdges] = useState<Edge[]>(initialEdges);

  const onNodesChange = useCallback(
    (changes: NodeChange<Node>[]) => setNodes((nds) => applyNodeChanges(changes, nds)),
    [],
  );
  const onEdgesChange = useCallback(
    (changes: EdgeChange<Edge>[]) => setEdges((eds) => applyEdgeChanges(changes, eds)),
    [],
  );

  return (
    <div className="flex h-full flex-col">
      <PageHeader 
        title="Shared Canvas & Autonomic Overlay" 
        description="The spatial workspace for real-time 3D CAD rendering and sub-agent state visualization." 
      />
      <div className="flex-1 w-full relative border rounded-md overflow-hidden bg-background">
        <ReactFlow
          nodes={nodes}
          nodeTypes={nodeTypes}
          onNodesChange={onNodesChange}
          edges={edges}
          onEdgesChange={onEdgesChange}
          fitView
          colorMode="system"
        >
          <Background gap={16} size={1} />
          <Controls />
        </ReactFlow>
      </div>
    </div>
  );
}
