import { useState } from "react";
import { supabase } from "../../utils/supabase";

function Register() {
  const [formulario, setFormulario] = useState({
    nombre: "",
    telefono: "",
    email: "",
    password: "",
  });

  const handleChange = (e) =>
    setFormulario({ ...formulario, [e.target.name]: e.target.value });

  async function handleSubmit(e) {
    e.preventDefault()
    try {
      const { error } = await supabase.auth.signUp({
        email: formulario.email ,
        password: formulario.password,
        options: {
          data: {
            nombre: formulario.nombre,
            telefono: formulario.telefono,
          },
        },
      });
      if (error) {
      console.error("Problemas con el registro");
    } else {
      console.log("Registro exitoso!");
    }
    } catch (error) {
        console.error(error);   
    }
  }

  return (
    <div>
      <form onSubmit={handleSubmit}>
        <input type="text" name="nombre" onChange={handleChange} />
        <input type="text" name="telefono" onChange={handleChange} />
        <input type="text" name="email" onChange={handleChange} />
        <input type="text" name="password" onChange={handleChange} />
        <input type="submit" value="Registrar cuenta" />
      </form>
    </div>
  );
}

export default Register;
