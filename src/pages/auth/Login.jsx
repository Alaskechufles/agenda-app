import { useState } from "react";
import { supabase } from "../../utils/supabase";

function Login() {
  const [formulario, setFormulario] = useState({
    email: "",
    password: "",
  });

  const handleChange = (e) =>
    setFormulario({ ...formulario, [e.target.name]: e.target.value });

  async function handleSubmit(e) {
    e.preventDefault()
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: formulario.email ,
        password: formulario.password,
      });
      if (error) {
      console.error("Problemas con el Inidio de Sesión");
    } else {
      console.log("Inicio de Sesión exitoso!");
    }
    } catch (error) {
        console.error(error);   
    }
  }

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <input type="text" name="email" onChange={handleChange} />
        <input type="text" name="password" onChange={handleChange} />
        <input type="submit" value="Iniciar Sesión" />
      </form>
    </div>
  );
}

export default Login;
