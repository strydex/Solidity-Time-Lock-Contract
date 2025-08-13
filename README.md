# !!!В РАЗРАБОТКЕ - НЕ ИСПОЛЬЗОВАТЬ ДО УВЕДОМЛЕНИЯ!!!

## 🚀 HTLC “Счёт Свободы”

Набор смарт-контрактов для организации неприкосновенного накопительного счёта на Ethereum с временной блокировкой средств. Позволяет использовать ERC20-токены, а также проводить обмен NFT и токенов через базовый HTLC.

***

### Содержание репозитория

1. **htlc-erc20-ru.sol**
Смарт-контракт `HashedTimelockERC20` – блокировка и разблокировка ERC20-токенов (USDT, USDC, DAI и др.).
2. **htlc-base-ru.sol**
Абстрактный контракт `HashedTimelockBase` – основа для двустороннего обмена: NFT ↔ ERC20.
3. **htlc-erc721-ru.sol**
Смарт-контракт `HashedTimelockERC721` – депонирование NFT (ERC721) с условной передачей.

***

## 🔍 Обзор контрактов

### **1. HashedTimelockERC20**

- **Назначение**: долгосрочное хранение и накопление ERC20-токенов
- **Ключевые функции**:
    - `newContract(receiver, hashlock, timelock, tokenContract, amount)`
    - `withdraw(contractId, preimage)`
    - `refund(contractId)`


### 2. HashedTimelockBase

- **Назначение**: фундамент для Atomic Swap (обмена NFT на токены)
- Не содержит функций создания и исполнения – служит базой для расширения.


### 3. HashedTimelockERC721

- **Назначение**: временная блокировка уникальных токенов (NFT)
- Практический эскроу-механизм для торга NFT.

***

## 📋 Зависимости

- Node.js ≥14 и npm
- Установленный [Hardhat](https://hardhat.org) или [Truffle](https://trufflesuite.com)
- MetaMask или любой другой Web3-кошелёк
- Адрес деплоя на тестнете (например, Ropsten) или Mainnet

***

## ⚙️ Установка и настройка

1. Склонировать репозиторий

```bash
git clone https://github.com/strydex/Solidity-Time-Lock-Contract.git
cd Solidity-Time-Lock-Contract
```

2. Установить зависимости

```bash
npm install
```

3. Настроить `.env`

```dotenv
INFURA_API_KEY=ваш_infura_key
PRIVATE_KEY=ваш_приватный_ключ
NETWORK=ropsten
```


***

## 🔨 Деплой смарт-контрактов

Пример с Hardhat:

1. В папке `contracts/` разместите три `.sol` файла.
2. Создайте файл `scripts/deploy.js`:

```javascript
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const ERC20HTLC = await ethers.getContractFactory("HashedTimelockERC20");
  const erc20htlc = await ERC20HTLC.deploy();
  await erc20htlc.deployed();
  console.log("ERC20 HTLC deployed to:", erc20htlc.address);

  const ERC721HTLC = await ethers.getContractFactory("HashedTimelockERC721");
  const erc721htlc = await ERC721HTLC.deploy();
  await erc721htlc.deployed();
  console.log("ERC721 HTLC deployed to:", erc721htlc.address);

  const BaseHTLC = await ethers.getContractFactory("HashedTimelockBase");
  const basehtlc = await BaseHTLC.deploy();
  await basehtlc.deployed();
  console.log("Base HTLC deployed to:", basehtlc.address);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
```

3. Запустить деплой:

```bash
npx hardhat run scripts/deploy.js --network $NETWORK
```


***

## 📝 Использование

### Создание “Счёта Свободы” (ERC20)

1. **Генерация секретного ключа**

```js
const secret = ethers.utils.randomBytes(32);
const hashlock = ethers.utils.sha256(secret);
```

2. **Approve токена**

```js
await tokenContract.connect(user).approve(htlcAddress, amount);
```

3. **Новый контракт**

```js
const tx = await htlc.newContract(
  user.address,
  hashlock,
  Math.floor(Date.now()/1000) + 365*24*3600,
  tokenContract.address,
  amount
);
await tx.wait();
```

4. **Вывод после завершения срока**
    - Если вы помните секрет — `withdraw(contractId, secret)`
    - Иначе — `refund(contractId)` после `timelock`

### Базовый обмен (Base) и NFT (ERC721)

- Для **Atomic Swap** наследуйте `HashedTimelockBase` и реализуйте функции обмена
- Для депонирования NFT используйте `HashedTimelockERC721` аналогично ERC20, но с `tokenId`

***

## ⚠️ Предостережения и советы

1. **Тщательно храните секрет** (preimage).
2. **Проверьте адреса** контрактов перед деплоем.
3. **Используйте тестовые сети** для отладки.
4. **Не раскомментируйте** условие `timelock > now` в `withdraw` без тщательного тестирования.
5. **Следите за газом**: ERC721 операции дороже ERC20.
6. **Аудитируйте** контракты перед mainnet.

***

## 🎯 Рекомендация

Для создания надёжного “счёта свободы” акцентируйте внимание на **htlc-erc20-ru.sol**:

- Простота кода
- Минимизация стоимости газа
- Поддержка стейблкоинов для стабильных накоплений

Желаю удачи в накоплении и защите ваших средств! 🛡️

