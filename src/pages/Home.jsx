import { useEffect } from "react";
import { useState } from "react";
import { supabase } from "../utils/supabase";

function Home() {
  const [servicios, setServicios] = useState([]);

  useEffect(() => {
    async function traerServicios() {
      try {
        let { data } = await supabase
          .from("servicios")
          .select("*");
        console.log(data)
        setServicios(data);
      } catch (error) {
        console.error(error);
      }
    }
    traerServicios()
  }, []);

  return (
  <div>
    {console.log(servicios)}
    <h1>Home</h1>
</div>);
}

export default Home;
