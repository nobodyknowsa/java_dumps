#!/bin/bash

# Проверка аргументов скрипта
# Тут укажите ваши неймспейсы
if [[ ! "$1" =~ ^(dev|uat|ha|prod)$ ]]; then
   echo "Ошибка: Неверный или отсутствующий namespace! Доступны: dev, uat, ha, prod."
   exit 1
fi

if [[ -z "$2" ]]; then
   echo "Ошибка: Не указано имя пода!"
   exit 1
fi

if [[ ! "$3" =~ ^(thread|heap|all)$ ]]; then
   echo "Ошибка: Неверный или отсутствующий тип дампа! Доступны: thread, heap, all."
   exit 1
fi

if [[ ! "$4" =~ ^(true|false)$ ]]; then
   echo "Ошибка: Не указано нужен ли рестарт! Доступны: true, false."
   exit 1
fi

#Получаем токен от волта чтоб использовать его для доступа к сикретам
echo "Авторизация в Vault..."
VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
export VAULT_TOKEN

echo "Получение kubeconfig из Vault..."

#Вытаскиваем содержимое нужного нам поля и указываем путь к кубконфигу 
vault kv get -format=json secret/kubeconfig | jq -r ".data.data[\"$1\"]" > /home/kubeconfig.yaml
export KUBECONFIG="/home/kubeconfig.yaml"


echo "Получаем список подов:"
# Получаем список подов, соответствующих указанному имени
list_services=$(kubectl get pods -n "$1" | awk '{print $1}' | grep "$2")
echo $list_services
# Обработка каждого пода в списке
for pod in ${list_services[@]}; do
    echo "Очистка временных файлов в ${pod}"
    kubectl exec -n "$1" "$pod" -- /bin/sh -c "rm -rf /tmp/*"

    case "$3" in
      thread)
        echo "Снятие thread dump с ${pod}"
        kubectl exec -n "$1" "$pod" -- /bin/sh -c "jstack 1 > /tmp/thread_dump.txt"
        kubectl cp "$pod:/tmp/thread_dump.txt" -n "$1" "thread_dump_${pod}.txt"
        ;;
        
      heap)
        echo "Снятие heap dump с ${pod}"
        kubectl exec -n "$1" "$pod" -- /bin/sh -c "jmap -dump:live,file=/tmp/heapdump.hprof 1"
        kubectl cp "$pod:/tmp/heapdump.hprof" -n "$1" "heap_dump_${pod}.hprof"
        ;;
        
      all)
        echo "Снятие thread и heap dump с ${pod}"
        kubectl exec -n "$1" "$pod" -- /bin/sh -c "jstack 1 > /tmp/thread_dump.txt"
        kubectl cp "$pod:/tmp/thread_dump.txt" -n "$1" "thread_dump_${pod}.txt"
        kubectl exec -n "$1" "$pod" -- /bin/sh -c "jmap -dump:live,file=/tmp/heapdump.hprof 1"
        kubectl cp "$pod:/tmp/heapdump.hprof" -n "$1" "heap_dump_${pod}.hprof"
        ;;
    esac
done

# Проверка на удаление подов после дампа
if [ "$4" == "true" ]; then
  for pod in ${list_services[@]}; do
    echo "Удаляем под ${pod}"
    kubectl delete po "$pod" -n "$1"
    echo "${pod} удален"
  done
fi
#Находим все файлы с расширением .hprof и .txt и помещаем в архив
find . -type f \( -name "*.hprof" -o -name "*.txt" \) -print0 | tar -czvf /tmp/"$3"_dump_"$2"_"$CI_PIPELINE_ID".tgz --null -T -

#Формируем ссылку
echo -e '\033[1;93m\n'
echo '#############################################'
echo 'DOWNLOAD'
echo '#############################################'
echo -e '\033[0m\n'
echo "Ваш дамп http://CHANGE-IP/dumps/"$3"_dump_"$2"_"$CI_PIPELINE_ID".tgz"
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
