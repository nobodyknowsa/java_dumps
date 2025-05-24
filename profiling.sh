#!/bin/bash

# Проверка аргументов скрипта

if [[ -z "$2" ]]; then
   echo "Ошибка: Не указано имя сервиса!"
   exit 1
fi

NAMESPACE="$1"
APP_NAME="$2"
ACTION="$3"

# Получение токена от Vault чтоб использовать его для доступа к сикретам
echo "Авторизация в Vault..."
VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
if [[ $? -ne 0 ]]; then
  echo "Ошибка авторизации в Vault"
  exit 1
fi
export VAULT_TOKEN

# Получение kubeconfig из Vault
# Вытаскиваем содержимое нужного нам поля и указываем путь к кубконфигу 
echo "Получение kubeconfig из Vault..."
KUBECONFIG_PATH="/home/kubeconfig.yaml"
vault kv get -format=json secret/kubeconfig | jq -r ".data.data[\"$NAMESPACE\"]" > "$KUBECONFIG_PATH"
if [[ $? -ne 0 ]]; then
  echo "Ошибка получения kubeconfig"
  exit 1
fi
export KUBECONFIG="$KUBECONFIG_PATH"

# Получение списка подов
echo "Получение списка подов..."
PODS=$(kubectl get pods -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name | grep "$APP_NAME")
if [[ -z "$PODS" ]]; then
  echo "Ошибка: поды для приложения $APP_NAME в неймспейсе $NAMESPACE не найдены"
  exit 1
fi
echo $PODS

# Функция для запуска профилирования
start_profiling() {
  local pod="$1"
  echo "Запуск профилирования на поде $pod..."
  kubectl exec -n "$NAMESPACE" "$pod" -- mkdir -p /tmp/profiling || {
    echo "Ошибка создания директории на поде $pod"
    return 1
  }
  kubectl cp ./profiling.jfc "$NAMESPACE/$pod:/tmp/profiling/profiling.jfc" || {
    echo "Ошибка копирования профиля на под $pod"
    return 1
  }
  kubectl exec -n "$NAMESPACE" "$pod" -- jcmd 1 JFR.start name=API filename=/tmp/profiling/recording.jfr disk=true maxsize=5g dumponexit=true settings=/tmp/profiling/profiling.jfc || {
    echo "Ошибка запуска профилирования на поде $pod"
    return 1
  }
}


stop_profiling() {
  local pod="$1"
  echo "Остановка профилирования в поде $pod..."
  kubectl exec -n "$NAMESPACE" "$pod" -- jcmd 1 JFR.stop name=API || {
    echo "Ошибка остановки профилирования на поде $pod"
    return 1
  }
  kubectl cp "$NAMESPACE/$pod:/tmp/profiling/recording.jfr" "./java_prof_${pod}.jfr" || {
    echo "Ошибка копирования записи профилирования с пода $pod"
    return 1
  }
  kubectl exec -n "$NAMESPACE" "$pod" -- rm -rf /tmp/profiling/* || {
    echo "Ошибка очистки директории на поде $pod"
    return 1
  }
}

# Обработка действия
for pod in $PODS; do
  if [[ "$ACTION" == "start" ]]; then
    start_profiling "$pod"
  elif [[ "$ACTION" == "stop" ]]; then
    stop_profiling "$pod"
  fi
done

# Информация
if [[ "$ACTION" == "start" ]]; then
  echo  "Профилирование запущено"
elif [[ "$ACTION" == "stop" ]]; then
  #Находим все файлы с расширением .jfr и помещаем в архив
  find . -type f \( -name "*.jfr" \) -print0 | tar -czvf /tmp/profile_"$APP_NAME"_"$CI_PIPELINE_ID".tgz --null -T -
  
  #Формируем ссылку
  echo -e '\033[1;93m\n'
  echo '#############################################'
  echo                  'DOWNLOAD'
  echo '#############################################'
  echo -e '\033[0m\n'
  echo "Ваш профиль http://10.229.8.154/dumps/profile_"$APP_NAME"_"$CI_PIPELINE_ID".tgz"
  echo "                 ⊂_ヽ"
  echo "                 　 ＼＼"
  echo "                 　　 ＼( ͡° ͜ʖ ͡°)"
  echo "                 　　　 >　⌒ヽ"
  echo "                 　　　/ 　 へ＼"
  echo "                 　　 /　　/　＼＼"
  echo "                 c==3 ﾚ　ノ　　 ヽ_つ"
  echo "                 　　/　/"
  echo "                 　 /　/|"
  echo "                 　(　(ヽ"
  echo "                 　|　|、＼"
  echo "                 　| 丿 ＼ ⌒) "
  echo "                 　| |　　) / "
  echo "                  ノ )　　Lﾉ "
  echo "                 (_／ "
fi
