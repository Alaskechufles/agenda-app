import { useEffect } from "react";
import { useState } from "react";
import { supabase } from "../utils/supabase";

function Home() {
  const [servicios, setServicios] = useState([]);

  useEffect(() => {
    async function traerServicios() {
      try {
        let { data } = await supabase.from("servicios").select("nombre,precio");
        setServicios(data);
      } catch (error) {
        console.error(error);
      }
    }
    traerServicios();
  }, []);

  return (
    <div>
      
      <h1>Home</h1>
      <section>
        {servicios.map((servicio, index)=>(
          <p key={index}>{servicio.nombre}</p>
        ))}
      </section>
    </div>
  );
}

export default Home;
