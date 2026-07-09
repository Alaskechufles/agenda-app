import { useEffect } from "react";
import { useState } from "react";
import { supabase } from "../utils/supabase";
import { useContext } from "react";
import { AuthContext } from "../context/AuthContext";
import { useNavigate } from "react-router-dom";

function Home() {
  const {perfil , cerrarSesion} = useContext(AuthContext)
  const [servicios, setServicios] = useState([]);
  const navigate = useNavigate()

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

  async function handleLogOut() {
    await cerrarSesion()
    navigate("/")
  }

  return (
    <div> 
      {console.log(perfil)}
      
      <h1>Home { perfil ? `Bienvenido ${perfil.nombre}` : "" }</h1>
      <section>
        {servicios.map((servicio, index)=>(
          <p key={index}>{servicio.nombre}</p>
        ))}
      </section>
      <button onClick={handleLogOut} >Cerrar Sesión</button>
    </div>
  );
}

export default Home;
