import { useEffect } from "react";
import { useState } from "react";
import { createContext } from "react";
import { supabase } from "../utils/supabase";

const AuthContext = createContext();

function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [perfil, setPerfil] = useState(null);

  useEffect(() => {
    async function verificarSesion() {
      const { data, error } = await supabase.auth.getSession();
      setSession(data);
      setLoading(false);
      if (error) {
        console.error("Problemas con identificar la sesión");
      } else {
        console.log("Sesión identificada");
      }
    }
    verificarSesion();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_OUT") {
        setSession(null);
      } else if (session) {
        setSession(session);
      }
    });
    return () => {
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    async function traerPerfil() {
      try {
        const { data, error } = await supabase
          .from("perfiles")
          .select("*")
          .eq("id", session.user.id)
          .single();
        setPerfil(data);
        if (error) {
          console.error("Problemas con traer el perfil");
        } else {
          console.log("Perfil cargado exitosamente");
        }
      } catch (error) {
        console.error(error);
      }
    }
    traerPerfil();
  }, [session]);

  async function cerrarSesion() {
    const { error } = await supabase.auth.signOut();
    if (error) {
      console.error("Problemas con cerrar sesión");
    } else {
      console.log("Sesion cerrada correctamente");
    }
  }

  const value = { session, loading, perfil, cerrarSesion };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export { AuthContext, AuthProvider };
