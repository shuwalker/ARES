import { useRef } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { Handle, Position } from '@xyflow/react';

function DemoGeometry() {
  const meshRef = useRef<any>(null);
  useFrame((_state, delta) => {
    if (meshRef.current) {
      meshRef.current.rotation.x += delta;
      meshRef.current.rotation.y += delta * 0.5;
    }
  });

  return (
    <mesh ref={meshRef}>
      <torusKnotGeometry args={[1, 0.3, 100, 16]} />
      <meshStandardMaterial color="#4f46e5" wireframe={true} />
    </mesh>
  );
}

export function CadViewerNode({ data }: { data: any }) {
  return (
    <div className="w-[400px] h-[300px] border border-border bg-card rounded-md shadow-md flex flex-col overflow-hidden">
      <div className="bg-muted px-3 py-2 border-b border-border font-semibold text-sm flex justify-between items-center cursor-move">
        <span>{data.label || '3D CAD Viewer'}</span>
        <span className="text-xs text-muted-foreground uppercase font-bold tracking-wider text-primary">Interactive</span>
      </div>
      <div className="flex-1 relative bg-black/5 nodrag cursor-grab active:cursor-grabbing">
        <Canvas camera={{ position: [0, 0, 5], fov: 50 }}>
          <ambientLight intensity={0.5} />
          <directionalLight position={[10, 10, 5]} intensity={1} />
          <DemoGeometry />
          <OrbitControls makeDefault />
        </Canvas>
      </div>
      <Handle type="target" position={Position.Left} className="w-3 h-3 border-2 bg-primary" />
      <Handle type="source" position={Position.Right} className="w-3 h-3 border-2 bg-primary" />
    </div>
  );
}
